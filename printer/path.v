module printer

/// A configuration for describing how paths should be written.
struct PathConfig implements IClone {
mut:
	colors     ColorSpecs
	hyperlink  HyperlinkConfig
	separator  ?u8
	terminator u8 = `\n`
}

/// A builder for a printer that emits file paths.
pub struct PathPrinterBuilder implements IClone {
mut:
	config PathConfig
}

/// Return a new path printer builder with a default configuration.
pub fn PathPrinterBuilder.new() PathPrinterBuilder {
	return PathPrinterBuilder{
		config: PathConfig{
			hyperlink: HyperlinkConfig.default()
		}
	}
}

/// Create a new path printer with the current configuration that writes
/// paths to the given writer.
pub fn (builder PathPrinterBuilder) build[W](wtr W) PathPrinter[W] {
	return PathPrinter[W]{
		config:       builder.config
		wtr:          wtr
		interpolator: Interpolator.new(&builder.config.hyperlink)
	}
}

/// Set the user color specifications to use for coloring in this printer.
///
/// A `UserColorSpec` can be constructed from a string in accordance with the
/// color specification format. See the `UserColorSpec` type documentation for
/// more details on the format. A `ColorSpecs` can then be generated from zero
/// or more `UserColorSpec`s.
///
/// Regardless of the color specifications provided here, whether color is
/// actually used or not is determined by the implementation of `WriteColor`
/// provided to `build`. For example, if `NoColor` is provided to `build`, then
/// no color will ever be printed regardless of the color specifications
/// provided here.
///
/// This completely overrides any previous color specifications. This does
/// not add to any previously provided color specifications on this builder.
///
/// The default color specifications provide no styling.
pub fn (mut builder PathPrinterBuilder) color_specs(specs ColorSpecs) &PathPrinterBuilder {
	builder.config.colors = specs
	return builder
}

/// Set the configuration to use for hyperlinks output by this printer.
///
/// Regardless of the hyperlink format provided here, whether hyperlinks are
/// actually used or not is determined by the implementation of `WriteColor`
/// provided to `build`. For example, if `NoColor` is provided to `build`, then
/// no hyperlinks will ever be printed regardless of the format provided here.
///
/// This completely overrides any previous hyperlink format.
///
/// The default configuration results in not emitting any hyperlinks.
pub fn (mut builder PathPrinterBuilder) hyperlink(config HyperlinkConfig) &PathPrinterBuilder {
	builder.config.hyperlink = config
	return builder
}

/// Set the path separator used when printing file paths.
///
/// Typically, printing is done by emitting the file path as is. However,
/// this setting provides the ability to use a different path separator
/// from what the current environment has configured.
///
/// A typical use for this option is to permit cygwin users on Windows to
/// set the path separator to `/` instead of using the system default of
/// `\`.
///
/// This is disabled by default.
pub fn (mut builder PathPrinterBuilder) separator(sep ?u8) &PathPrinterBuilder {
	builder.config.separator = sep
	return builder
}

/// Set the path terminator used.
///
/// The path terminator is a byte that is printed after every file path
/// emitted by this printer.
///
/// The default path terminator is `\n`.
pub fn (mut builder PathPrinterBuilder) terminator(terminator u8) &PathPrinterBuilder {
	builder.config.terminator = terminator
	return builder
}

/// A printer file paths, with optional color and hyperlink support.
///
/// This printer is very similar to `Summary` in that it principally only emits
/// file paths. The main difference is that this printer doesn't actually
/// execute any search via a `Sink` implementation, and instead just provides a
/// way for the caller to print paths.
///
/// A caller could just print the paths themselves, but this printer handles a
/// few details:
///
/// * It can normalize path separators.
/// * It permits configuring the terminator.
/// * It allows setting the color configuration in a way that is consistent
///   with the other printers in this crate.
/// * It allows setting the hyperlink format in a way that is consistent with
///   the other printers in this crate.
pub struct PathPrinter[W] {
	config PathConfig
mut:
	wtr          W
	interpolator Interpolator
}

/// Write the given path to the underlying writer.
pub fn (mut pp PathPrinter[W]) write[^p](path &^p string) ! {
	$if W is WriteColor {
		mut ppath := PrinterPath.new(path).with_separator(pp.config.separator)
		defer {
			ppath.free()
		}
		bytes := ppath.as_bytes()
		if !pp.wtr.supports_color() {
			pp.wtr.write(bytes)!
		} else {
			status := pp.start_hyperlink(ppath)!
			pp.wtr.set_color(pp.config.colors.path())!
			pp.wtr.write(bytes)!
			pp.wtr.reset()!
			pp.interpolator.finish(status, mut pp.wtr)!
		}
		pp.wtr.write([pp.config.terminator])!
	} $else {
		_ = path
		return error('PathPrinter requires a WriteColor implementation')
	}
}

/// Flush the underlying writer.
pub fn (mut pp PathPrinter[W]) flush() ! {
	$if W is WriteColor {
		pp.wtr.flush()!
	}
}

/// Starts a hyperlink span when applicable.
fn (mut pp PathPrinter[W]) start_hyperlink[^p](mut path PrinterPath[^p]) !InterpolatorStatus {
	$if W is WriteColor {
		if pp.config.hyperlink.format().is_empty() {
			return InterpolatorStatus.inactive()
		}
		hyperpath := path.as_hyperlink() or { return InterpolatorStatus.inactive() }
		values := Values.new(hyperpath)
		return pp.interpolator.begin(&values, mut pp.wtr)
	} $else {
		_ = path
		return InterpolatorStatus.inactive()
	}
}
