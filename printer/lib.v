module printer

/*
This crate provides featureful and fast printers that interoperate with the
`grep-searcher` crate.

# Brief overview

The `Standard` printer shows results in a human readable format, and is
modeled after the formats used by standard grep-like tools. Features include,
but are not limited to, cross platform terminal coloring, search & replace,
multi-line result handling and reporting summary statistics.

The `JSON` printer shows results in a machine readable format.
To facilitate a stream of search results, the format uses JSON
Lines by emitting a series of messages as search
results are found.

The `Summary` printer shows aggregate results for a single search in a
human readable format, and is modeled after similar formats found in standard
grep-like tools. This printer is useful for showing the total number of matches
and/or printing file paths that either contain or don't contain matches.
*/

// The maximum number of bytes to execute a search to account for look-ahead.
//
// This is an unfortunate kludge since PCRE2 doesn't provide a way to search
// a substring of some input while accounting for look-ahead. In theory, we
// could refactor the various 'grep' interfaces to account for it, but it would
// be a large change. So for now, we just let PCRE2 go looking a bit for a
// match without searching the entire rest of the contents.
//
// Note that this kludge is only active in multi-line mode.
pub const max_look_ahead = usize(128)
