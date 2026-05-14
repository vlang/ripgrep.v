module printer

/// A configuration for describing how paths should be written.
struct PathConfig {
mut:
	colors     ColorSpecs
	hyperlink  HyperlinkConfig
	separator  ?u8
	terminator u8 = `\n`
}

/// A builder for a printer that emits file paths.
pub struct PathPrinterBuilder {
mut:
	config PathConfig
}

/// Return a new path printer builder with a default configuration.
pub fn PathPrinterBuilder.new() PathPrinterBuilder {
	return PathPrinterBuilder{}
}

/// Create a new path printer with the current configuration that writes
/// paths to the given writer.
pub fn (builder PathPrinterBuilder) build[W](wtr W) PathPrinter[W] {
	return PathPrinter[W]{
		config:       builder.config
		wtr:          wtr
		interpolator: Interpolator.new(builder.config.hyperlink)
	}
}

/// Set the user color specifications to use for coloring in this printer.
pub fn (mut builder PathPrinterBuilder) color_specs(specs ColorSpecs) &PathPrinterBuilder {
	builder.config.colors = specs
	return builder
}

/// Set the configuration to use for hyperlinks output by this printer.
pub fn (mut builder PathPrinterBuilder) hyperlink(config HyperlinkConfig) &PathPrinterBuilder {
	builder.config.hyperlink = config
	return builder
}

/// Set the path separator used when printing file paths.
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
pub struct PathPrinter[W] {
	config PathConfig
mut:
	wtr          W
	interpolator Interpolator
}

/// Write the given path to the underlying writer.
pub fn (mut printer PathPrinter[W]) write[^p](path &^p string) ! {
	$if W is WriteColor {
		ppath := PrinterPath.new(path).with_separator(printer.config.separator)
		bytes := ppath.as_bytes()
		if !printer.wtr.supports_color() {
			printer.wtr.write(bytes)!
		} else {
			status := printer.start_hyperlink(ppath)!
			printer.wtr.set_color(printer.config.colors.path())!
			printer.wtr.write(bytes)!
			printer.wtr.reset()!
			printer.interpolator.finish(status, mut printer.wtr)!
		}
		printer.wtr.write([printer.config.terminator])!
	} $else {
		_ = path
		return error('PathPrinter requires a WriteColor implementation')
	}
}

/// Starts a hyperlink span when applicable.
fn (mut printer PathPrinter[W]) start_hyperlink[^p](mut path PrinterPath[^p]) !InterpolatorStatus {
	$if W is WriteColor {
		hyperpath := path.as_hyperlink() or { return InterpolatorStatus.inactive() }
		values := Values.new(hyperpath)
		return printer.interpolator.begin(values, mut printer.wtr)
	} $else {
		_ = path
		return InterpolatorStatus.inactive()
	}
}
