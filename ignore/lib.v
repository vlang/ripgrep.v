module ignore

/*
The ignore crate provides a fast recursive directory iterator that respects
various filters such as globs, file types and `.gitignore` files. The precise
matching rules and precedence is explained in the documentation for
`WalkBuilder`.

Secondarily, this crate exposes gitignore and file type matchers for use cases
that demand more fine-grained control.

# Example

This example shows the most basic usage of this crate. This code will
recursively traverse the current directory while automatically filtering out
files and directories according to ignore globs found in files like
`.ignore` and `.gitignore`:

```v
mut walk := Walk.new('./')
for {
	result := walk.next() or { break }
	if result.is_error {
		println('ERROR: ${result.err.msg()}')
	} else {
		println(result.entry.path())
	}
}
```

# Example: advanced

By default, the recursive directory iterator will ignore hidden files and
directories. This can be disabled by building the iterator with `WalkBuilder`:

```v
mut walk := WalkBuilder.new('./').hidden(false).build()
for {
	result := walk.next() or { break }
	println(result)
}
```

See the documentation for `WalkBuilder` for many other options.
*/
