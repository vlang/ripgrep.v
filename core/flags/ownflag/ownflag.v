module ownflag

// This module provides the ownership-safe subset of V's flag mapping API that
// translated code uses when `vlib/flag` must remain ownership-free.

pub struct ParsedFlag {
pub:
	raw        string
	field_name string
	delimiter  string
	name       string
	arg        ?string
	pos        int
	repeats    int
}

pub enum ParseMode {
	strict
	relaxed
}

pub enum Style {
	short
	long
	short_long
}

@[params]
pub struct ParseConfig {
pub:
	delimiter string    = '-'
	mode      ParseMode = .strict
	style     Style     = .short_long
	stop      ?string
	skip      u16
}

pub struct FlagDef implements IClone {
pub:
	field_name string
	long_name  string
	short_name string
	takes_arg  bool
}

pub struct FlagMapper {
pub:
	config ParseConfig @[required]
	input  []string    @[required]
mut:
	long_defs    map[string]FlagDef
	short_defs   map[string]FlagDef
	all_flags    []ParsedFlag
	handled_pos  []int
	no_match_pos []int
}

fn normalize_attr_value(value string) string {
	trimmed := value.trim_space()
	if trimmed.len > 1 {
		if (trimmed[0] == `'` && trimmed[trimmed.len - 1] == `'`)
			|| (trimmed[0] == `"` && trimmed[trimmed.len - 1] == `"`) {
			return trimmed[1..trimmed.len - 1].to_owned()
		}
	}
	return trimmed.to_owned()
}

fn parse_attrs(attrs []string) map[string]string {
	mut out := map[string]string{}
	for attr in attrs {
		if attr.contains(':') {
			parts := attr.split_nth(':', 2)
			if parts.len == 2 {
				out[parts[0].trim_space().to_owned()] = normalize_attr_value(parts[1])
			}
		} else {
			out[attr.trim_space().to_owned()] = 'true'.to_owned()
		}
	}
	return out
}

fn require_short_name(field_name string, value string) !string {
	if value.len != 1 {
		return error('attribute @[short: ${value}] on ${field_name} can only be a single character')
	}
	return value.to_owned()
}

fn (mut fm FlagMapper) reset_state() {
	fm.long_defs = map[string]FlagDef{}
	fm.short_defs = map[string]FlagDef{}
	fm.all_flags = []ParsedFlag{}
	fm.handled_pos = []int{}
	fm.no_match_pos = []int{}
}

fn (mut fm FlagMapper) register_flag(def FlagDef) ! {
	if def.long_name != '' {
		if existing := fm.long_defs[def.long_name] {
			return error('flag name "${def.long_name}" is already registered to ${existing.field_name}')
		}
		fm.long_defs[def.long_name] = def
	}
	if def.short_name != '' {
		if existing := fm.short_defs[def.short_name] {
			return error('flag short name "${def.short_name}" is already registered to ${existing.field_name}')
		}
		fm.short_defs[def.short_name] = def
	}
}

fn (mut fm FlagMapper) build_schema[T]() ! {
	$if T is $struct {
		$for field in T.fields {
			attrs := parse_attrs(field.attrs)
			if 'ignore' in attrs {
				continue
			}
			mut def := FlagDef{
				field_name: field.name.to_owned()
				long_name:  field.name.replace('_', '-').to_owned()
			}
			if long_name := attrs['long'] {
				def.long_name = long_name.replace('_', '-').to_owned()
			}
			if only_name := attrs['only'] {
				if only_name.len == 0 {
					return error('attribute @[only] on ${field.name} can not be empty, use @[only: x]')
				}
				if only_name.len == 1 {
					def.long_name = ''
					def.short_name = require_short_name(field.name, only_name)!
				} else {
					def.long_name = only_name.replace('_', '-').to_owned()
					def.short_name = ''
				}
			}
			if short_name := attrs['short'] {
				def.short_name = require_short_name(field.name, short_name)!
			}
			$if field.typ is bool {
				def.takes_arg = false
			} $else $if field.typ is string {
				def.takes_arg = true
			} $else $if field.typ is int {
				if 'repeats' !in attrs {
					return error('unsupported int flag field ${field.name} without @[repeats]')
				}
				def.takes_arg = false
			} $else {
				return error('unsupported flag field ${field.name} type ${typeof(field).name}')
			}
			fm.register_flag(def)!
		}
	} $else {
		return error('FlagMapper.parse expects a struct type')
	}
}

fn (mut fm FlagMapper) record(parsed ParsedFlag, extra_positions []int) {
	fm.all_flags << parsed
	fm.handled_pos << parsed.pos
	for pos in extra_positions {
		fm.handled_pos << pos
	}
}

fn (mut fm FlagMapper) parse_long_arg(arg string, pos int) !bool {
	if !arg.starts_with('--') || arg == '--' {
		return false
	}
	body := arg[2..]
	if body.len == 0 {
		return false
	}
	mut name := body
	mut value := ''
	mut has_value := false
	if eq := body.index('=') {
		name = body[..eq].to_owned()
		value = body[eq + 1..].to_owned()
		has_value = true
	}
	def := fm.long_defs[name] or {
		if fm.config.mode == .relaxed {
			fm.no_match_pos << pos
			return false
		}
		return error('unknown flag --${name}')
	}
	if def.takes_arg {
		mut parsed_arg := value.clone()
		mut extra_positions := []int{}
		if !has_value {
			if pos + 1 >= fm.input.len {
				return error('missing value for --${name}')
			}
			parsed_arg = fm.input[pos + 1].to_owned()
			extra_positions << pos + 1
		}
		fm.record(ParsedFlag{
			raw:        arg.to_owned()
			field_name: def.field_name
			delimiter:  '--'
			name:       name.clone()
			arg:        parsed_arg
			pos:        pos
			repeats:    1
		}, extra_positions)
		return true
	}
	if has_value {
		return error('flag --${name} does not take a value')
	}
	fm.record(ParsedFlag{
		raw:        arg.to_owned()
		field_name: def.field_name
		delimiter:  '--'
		name:       name.clone()
		arg:        none
		pos:        pos
		repeats:    1
	}, []int{})
	return true
}

fn (mut fm FlagMapper) parse_short_arg(arg string, pos int) !bool {
	if !arg.starts_with('-') || arg.starts_with('--') || arg == '-' {
		return false
	}
	body := arg[1..]
	if body.len == 0 {
		return false
	}
	mut parsed_flags := []ParsedFlag{}
	mut extra_positions := []int{}
	mut i := 0
	for i < body.len {
		name := body[i].ascii_str()
		def := fm.short_defs[name] or {
			if fm.config.mode == .relaxed {
				return false
			}
			return error('unknown flag -${name}')
		}
		if def.takes_arg {
			mut parsed_arg := ''
			if i + 1 < body.len {
				parsed_arg = body[i + 1..].to_owned()
			} else {
				if pos + 1 >= fm.input.len {
					return error('missing value for -${name}')
				}
				parsed_arg = fm.input[pos + 1].to_owned()
				extra_positions << pos + 1
			}
			parsed_flags << ParsedFlag{
				raw:        arg.to_owned()
				field_name: def.field_name
				delimiter:  '-'
				name:       name
				arg:        parsed_arg
				pos:        pos
				repeats:    1
			}
			i = body.len
			continue
		}
		parsed_flags << ParsedFlag{
			raw:        arg.to_owned()
			field_name: def.field_name
			delimiter:  '-'
			name:       name
			arg:        none
			pos:        pos
			repeats:    1
		}
		i++
	}
	if parsed_flags.len == 0 {
		return false
	}
	for index, parsed in parsed_flags {
		fm.record(parsed, if index == 0 { extra_positions.clone() } else { []int{} })
	}
	return true
}

fn (mut fm FlagMapper) parse_registered_flags() ! {
	start := int(fm.config.skip)
	mut i := start
	for i < fm.input.len {
		if i in fm.handled_pos {
			i++
			continue
		}
		arg := fm.input[i]
		if stop := fm.config.stop {
			if arg == stop {
				break
			}
		}
		if fm.parse_long_arg(arg, i)! {
			i++
			continue
		}
		if fm.parse_short_arg(arg, i)! {
			i++
			continue
		}
		i++
	}
}

pub fn (mut fm FlagMapper) parse_defs(defs []FlagDef) ! {
	fm.reset_state()
	if fm.config.style != .short_long {
		return error('ownflag only supports short_long parsing')
	}
	for def in defs {
		fm.register_flag(def.clone())!
	}
	fm.parse_registered_flags()!
}

pub fn (mut fm FlagMapper) parse[T]() ! {
	fm.reset_state()
	if fm.config.style != .short_long {
		return error('ownflag only supports short_long parsing')
	}
	fm.build_schema[T]()!
	fm.parse_registered_flags()!
}

pub fn (fm &FlagMapper) parsed_flags() []ParsedFlag {
	return fm.all_flags.clone()
}

pub fn (fm &FlagMapper) handled_positions() []int {
	return fm.handled_pos.clone()
}

pub fn (fm &FlagMapper) no_matches() []string {
	mut out := []string{cap: fm.no_match_pos.len}
	for pos in fm.no_match_pos {
		out << fm.input[pos].to_owned()
	}
	return out
}
