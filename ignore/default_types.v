module ignore

/// This list represents the default file types that ripgrep ships with. In
/// general, any file format is fair game, although it should generally be
/// limited to reasonably popular open formats. For other cases, you can add
/// types to each invocation of ripgrep with the '--type-add' flag.
///
/// If you would like to add or improve this list, please file a PR:
/// <https://github.com/BurntSushi/ripgrep>.
///
/// Please try to keep this list sorted lexicographically and wrapped to 79
/// columns (inclusive).
struct DefaultTypeDef implements IClone {
	names []string
	globs []string
}

fn default_types() []DefaultTypeDef {
	return [
		DefaultTypeDef{
			names: ['ada']
			globs: ['*.adb', '*.ads']
		},
		DefaultTypeDef{
			names: ['agda']
			globs: ['*.agda', '*.lagda']
		},
		DefaultTypeDef{
			names: ['aidl']
			globs: ['*.aidl']
		},
		DefaultTypeDef{
			names: ['alire']
			globs: ['alire.toml']
		},
		DefaultTypeDef{
			names: ['amake']
			globs: ['*.mk', '*.bp']
		},
		DefaultTypeDef{
			names: ['asciidoc']
			globs: ['*.adoc', '*.asc', '*.asciidoc']
		},
		DefaultTypeDef{
			names: ['asm']
			globs: ['*.asm', '*.s', '*.S']
		},
		DefaultTypeDef{
			names: ['asp']
			globs: ['*.aspx', '*.aspx.cs', '*.aspx.vb', '*.ascx', '*.ascx.cs', '*.ascx.vb', '*.asp']
		},
		DefaultTypeDef{
			names: ['ats']
			globs: ['*.ats', '*.dats', '*.sats', '*.hats']
		},
		DefaultTypeDef{
			names: ['avro']
			globs: ['*.avdl', '*.avpr', '*.avsc']
		},
		DefaultTypeDef{
			names: ['awk']
			globs: ['*.awk']
		},
		DefaultTypeDef{
			names: ['bat', 'batch']
			globs: ['*.bat']
		},
		DefaultTypeDef{
			names: ['bazel']
			globs: ['*.bazel', '*.bzl', '*.BUILD', '*.bazelrc', 'BUILD', 'MODULE.bazel', 'WORKSPACE', 'WORKSPACE.bazel', 'WORKSPACE.bzlmod']
		},
		DefaultTypeDef{
			names: ['bitbake']
			globs: ['*.bb', '*.bbappend', '*.bbclass', '*.conf', '*.inc']
		},
		DefaultTypeDef{
			names: ['boxlang']
			globs: ['*.bx', '*.bxm', '*.bxs']
		},
		DefaultTypeDef{
			names: ['brotli']
			globs: ['*.br']
		},
		DefaultTypeDef{
			names: ['buildstream']
			globs: ['*.bst']
		},
		DefaultTypeDef{
			names: ['bzip2']
			globs: ['*.bz2', '*.tbz2']
		},
		DefaultTypeDef{
			names: ['c']
			globs: []
		},
		DefaultTypeDef{
			names: ['cabal']
			globs: ['*.cabal']
		},
		DefaultTypeDef{
			names: ['candid']
			globs: ['*.did']
		},
		DefaultTypeDef{
			names: ['carp']
			globs: ['*.carp']
		},
		DefaultTypeDef{
			names: ['cbor']
			globs: ['*.cbor']
		},
		DefaultTypeDef{
			names: ['ceylon']
			globs: ['*.ceylon']
		},
		DefaultTypeDef{
			names: ['cfml']
			globs: ['*.cfc', '*.cfm']
		},
		DefaultTypeDef{
			names: ['clojure']
			globs: ['*.clj', '*.cljc', '*.cljs', '*.cljx']
		},
		DefaultTypeDef{
			names: ['cmake']
			globs: ['*.cmake', 'CMakeLists.txt']
		},
		DefaultTypeDef{
			names: ['cmd']
			globs: ['*.bat', '*.cmd']
		},
		DefaultTypeDef{
			names: ['cml']
			globs: ['*.cml']
		},
		DefaultTypeDef{
			names: ['coffeescript']
			globs: ['*.coffee']
		},
		DefaultTypeDef{
			names: ['config']
			globs: ['*.cfg', '*.conf', '*.config', '*.ini']
		},
		DefaultTypeDef{
			names: ['container']
			globs: ['*Containerfile*', '*Dockerfile*']
		},
		DefaultTypeDef{
			names: ['coq']
			globs: ['*.v']
		},
		DefaultTypeDef{
			names: ['cpp']
			globs: []
		},
		DefaultTypeDef{
			names: ['creole']
			globs: ['*.creole']
		},
		DefaultTypeDef{
			names: ['crystal']
			globs: ['Projectfile', '*.cr', '*.ecr', 'shard.yml']
		},
		DefaultTypeDef{
			names: ['cs']
			globs: ['*.cs']
		},
		DefaultTypeDef{
			names: ['csharp']
			globs: ['*.cs']
		},
		DefaultTypeDef{
			names: ['cshtml']
			globs: ['*.cshtml']
		},
		DefaultTypeDef{
			names: ['csproj']
			globs: ['*.csproj']
		},
		DefaultTypeDef{
			names: ['css']
			globs: ['*.css', '*.scss']
		},
		DefaultTypeDef{
			names: ['csv']
			globs: ['*.csv']
		},
		DefaultTypeDef{
			names: ['cuda']
			globs: ['*.cu', '*.cuh']
		},
		DefaultTypeDef{
			names: ['cython']
			globs: ['*.pyx', '*.pxi', '*.pxd']
		},
		DefaultTypeDef{
			names: ['d']
			globs: ['*.d']
		},
		DefaultTypeDef{
			names: ['dart']
			globs: ['*.dart']
		},
		DefaultTypeDef{
			names: ['devicetree']
			globs: ['*.dts', '*.dtsi', '*.dtso']
		},
		DefaultTypeDef{
			names: ['dhall']
			globs: ['*.dhall']
		},
		DefaultTypeDef{
			names: ['diff']
			globs: ['*.patch', '*.diff']
		},
		DefaultTypeDef{
			names: ['dita']
			globs: ['*.dita', '*.ditamap', '*.ditaval']
		},
		DefaultTypeDef{
			names: ['docker']
			globs: ['*Dockerfile*']
		},
		DefaultTypeDef{
			names: ['dockercompose']
			globs: ['docker-compose.yml', 'docker-compose.*.yml']
		},
		DefaultTypeDef{
			names: ['dts']
			globs: ['*.dts', '*.dtsi']
		},
		DefaultTypeDef{
			names: ['dvc']
			globs: ['Dvcfile', '*.dvc']
		},
		DefaultTypeDef{
			names: ['ebuild']
			globs: ['*.ebuild', '*.eclass']
		},
		DefaultTypeDef{
			names: ['edn']
			globs: ['*.edn']
		},
		DefaultTypeDef{
			names: ['elisp']
			globs: ['*.el']
		},
		DefaultTypeDef{
			names: ['elixir']
			globs: ['*.ex', '*.eex', '*.exs', '*.heex', '*.leex', '*.livemd']
		},
		DefaultTypeDef{
			names: ['elm']
			globs: ['*.elm']
		},
		DefaultTypeDef{
			names: ['erb']
			globs: ['*.erb']
		},
		DefaultTypeDef{
			names: ['erlang']
			globs: ['*.erl', '*.hrl']
		},
		DefaultTypeDef{
			names: ['fennel']
			globs: ['*.fnl']
		},
		DefaultTypeDef{
			names: ['fidl']
			globs: ['*.fidl']
		},
		DefaultTypeDef{
			names: ['fish']
			globs: ['*.fish']
		},
		DefaultTypeDef{
			names: ['flatbuffers']
			globs: ['*.fbs']
		},
		DefaultTypeDef{
			names: ['fortran']
			globs: ['*.f', '*.F', '*.f77', '*.F77', '*.pfo', '*.f90', '*.F90', '*.f95', '*.F95']
		},
		DefaultTypeDef{
			names: ['fsharp']
			globs: ['*.fs', '*.fsx', '*.fsi']
		},
		DefaultTypeDef{
			names: ['fut']
			globs: ['*.fut']
		},
		DefaultTypeDef{
			names: ['gap']
			globs: ['*.g', '*.gap', '*.gi', '*.gd', '*.tst']
		},
		DefaultTypeDef{
			names: ['gdscript']
			globs: ['*.gd']
		},
		DefaultTypeDef{
			names: ['gleam']
			globs: ['*.gleam']
		},
		DefaultTypeDef{
			names: ['gn']
			globs: ['*.gn', '*.gni']
		},
		DefaultTypeDef{
			names: ['go']
			globs: ['*.go']
		},
		DefaultTypeDef{
			names: ['gprbuild']
			globs: ['*.gpr']
		},
		DefaultTypeDef{
			names: ['gradle']
			globs: ['*.gradle', '*.gradle.kts', 'gradle.properties', 'gradle-wrapper.*', 'gradlew', 'gradlew.bat']
		},
		DefaultTypeDef{
			names: ['graphql']
			globs: ['*.graphql', '*.graphqls']
		},
		DefaultTypeDef{
			names: ['groovy']
			globs: ['*.groovy', '*.gradle']
		},
		DefaultTypeDef{
			names: ['gzip']
			globs: ['*.gz', '*.tgz']
		},
		DefaultTypeDef{
			names: ['h']
			globs: ['*.h', '*.hh', '*.hpp']
		},
		DefaultTypeDef{
			names: ['haml']
			globs: ['*.haml']
		},
		DefaultTypeDef{
			names: ['hare']
			globs: ['*.ha']
		},
		DefaultTypeDef{
			names: ['haskell']
			globs: ['*.hs', '*.lhs', '*.cpphs', '*.c2hs', '*.hsc']
		},
		DefaultTypeDef{
			names: ['hbs']
			globs: ['*.hbs']
		},
		DefaultTypeDef{
			names: ['hs']
			globs: ['*.hs', '*.lhs']
		},
		DefaultTypeDef{
			names: ['html']
			globs: ['*.htm', '*.html', '*.ejs']
		},
		DefaultTypeDef{
			names: ['hy']
			globs: ['*.hy']
		},
		DefaultTypeDef{
			names: ['idris']
			globs: ['*.idr', '*.lidr']
		},
		DefaultTypeDef{
			names: ['janet']
			globs: ['*.janet']
		},
		DefaultTypeDef{
			names: ['java']
			globs: ['*.java', '*.jsp', '*.jspx', '*.properties']
		},
		DefaultTypeDef{
			names: ['jinja']
			globs: ['*.j2', '*.jinja', '*.jinja2']
		},
		DefaultTypeDef{
			names: ['jl']
			globs: ['*.jl']
		},
		DefaultTypeDef{
			names: ['js']
			globs: ['*.js', '*.jsx', '*.vue', '*.cjs', '*.mjs']
		},
		DefaultTypeDef{
			names: ['json']
			globs: ['*.json', 'composer.lock', '*.sarif']
		},
		DefaultTypeDef{
			names: ['jsonl']
			globs: ['*.jsonl']
		},
		DefaultTypeDef{
			names: ['julia']
			globs: ['*.jl']
		},
		DefaultTypeDef{
			names: ['jupyter']
			globs: ['*.ipynb', '*.jpynb']
		},
		DefaultTypeDef{
			names: ['k']
			globs: ['*.k']
		},
		DefaultTypeDef{
			names: ['kconfig']
			globs: ['Kconfig', 'Kconfig.*']
		},
		DefaultTypeDef{
			names: ['kotlin']
			globs: ['*.kt', '*.kts']
		},
		DefaultTypeDef{
			names: ['lean']
			globs: ['*.lean']
		},
		DefaultTypeDef{
			names: ['less']
			globs: ['*.less']
		},
		DefaultTypeDef{
			names: ['license']
			globs: ['COPYING']
		},
		DefaultTypeDef{
			names: ['lilypond']
			globs: ['*.ly', '*.ily']
		},
		DefaultTypeDef{
			names: ['lisp']
			globs: ['*.el', '*.jl', '*.lisp', '*.lsp', '*.sc', '*.scm']
		},
		DefaultTypeDef{
			names: ['llvm']
			globs: ['*.ll']
		},
		DefaultTypeDef{
			names: ['lock']
			globs: ['*.lock', 'package-lock.json']
		},
		DefaultTypeDef{
			names: ['log']
			globs: ['*.log']
		},
		DefaultTypeDef{
			names: ['lua']
			globs: ['*.lua']
		},
		DefaultTypeDef{
			names: ['lz4']
			globs: ['*.lz4']
		},
		DefaultTypeDef{
			names: ['lzma']
			globs: ['*.lzma']
		},
		DefaultTypeDef{
			names: ['m4']
			globs: ['*.ac', '*.m4']
		},
		DefaultTypeDef{
			names: ['make']
			globs: []
		},
		DefaultTypeDef{
			names: ['mako']
			globs: ['*.mako', '*.mao']
		},
		DefaultTypeDef{
			names: ['man']
			globs: []
		},
		DefaultTypeDef{
			names: ['markdown', 'md']
			globs: ['*.markdown', '*.md', '*.mdown', '*.mdwn', '*.mkd', '*.mkdn', '*.mdx']
		},
		DefaultTypeDef{
			names: ['matlab']
			globs: ['*.m']
		},
		DefaultTypeDef{
			names: ['meson']
			globs: ['meson.build', 'meson_options.txt', 'meson.options']
		},
		DefaultTypeDef{
			names: ['minified']
			globs: ['*.min.html', '*.min.css', '*.min.js']
		},
		DefaultTypeDef{
			names: ['mint']
			globs: ['*.mint']
		},
		DefaultTypeDef{
			names: ['mk']
			globs: ['mkfile']
		},
		DefaultTypeDef{
			names: ['ml']
			globs: ['*.ml']
		},
		DefaultTypeDef{
			names: ['motoko']
			globs: ['*.mo']
		},
		DefaultTypeDef{
			names: ['msbuild']
			globs: ['*.csproj', '*.fsproj', '*.vcxproj', '*.proj', '*.props', '*.targets', '*.sln', '*.slnf']
		},
		DefaultTypeDef{
			names: ['nim']
			globs: ['*.nim', '*.nimf', '*.nimble', '*.nims']
		},
		DefaultTypeDef{
			names: ['nix']
			globs: ['*.nix']
		},
		DefaultTypeDef{
			names: ['objc']
			globs: ['*.h', '*.m']
		},
		DefaultTypeDef{
			names: ['objcpp']
			globs: ['*.h', '*.mm']
		},
		DefaultTypeDef{
			names: ['ocaml']
			globs: ['*.ml', '*.mli', '*.mll', '*.mly']
		},
		DefaultTypeDef{
			names: ['org']
			globs: ['*.org', '*.org_archive']
		},
		DefaultTypeDef{
			names: ['pants']
			globs: ['BUILD']
		},
		DefaultTypeDef{
			names: ['pascal']
			globs: ['*.pas', '*.dpr', '*.lpr', '*.pp', '*.inc']
		},
		DefaultTypeDef{
			names: ['pdf']
			globs: ['*.pdf']
		},
		DefaultTypeDef{
			names: ['perl']
			globs: ['*.perl', '*.pl', '*.PL', '*.plh', '*.plx', '*.pm', '*.t']
		},
		DefaultTypeDef{
			names: ['php']
			globs: ['*.php', '*.php3', '*.php4', '*.php5', '*.php7', '*.php8', '*.pht', '*.phtml']
		},
		DefaultTypeDef{
			names: ['po']
			globs: ['*.po']
		},
		DefaultTypeDef{
			names: ['pod']
			globs: ['*.pod']
		},
		DefaultTypeDef{
			names: ['postscript']
			globs: ['*.eps', '*.ps']
		},
		DefaultTypeDef{
			names: ['prolog']
			globs: ['*.pl', '*.pro', '*.prolog', '*.P']
		},
		DefaultTypeDef{
			names: ['protobuf']
			globs: ['*.proto']
		},
		DefaultTypeDef{
			names: ['ps']
			globs: ['*.cdxml', '*.ps1', '*.ps1xml', '*.psd1', '*.psm1']
		},
		DefaultTypeDef{
			names: ['puppet']
			globs: ['*.epp', '*.erb', '*.pp', '*.rb']
		},
		DefaultTypeDef{
			names: ['purs']
			globs: ['*.purs']
		},
		DefaultTypeDef{
			names: ['py', 'python']
			globs: ['*.py', '*.pyi']
		},
		DefaultTypeDef{
			names: ['qmake']
			globs: ['*.pro', '*.pri', '*.prf']
		},
		DefaultTypeDef{
			names: ['qml']
			globs: ['*.qml']
		},
		DefaultTypeDef{
			names: ['qrc']
			globs: ['*.qrc']
		},
		DefaultTypeDef{
			names: ['qui']
			globs: ['*.ui']
		},
		DefaultTypeDef{
			names: ['r']
			globs: ['*.R', '*.r', '*.Rmd', '*.rmd', '*.Rnw', '*.rnw']
		},
		DefaultTypeDef{
			names: ['racket']
			globs: ['*.rkt']
		},
		DefaultTypeDef{
			names: ['raku']
			globs: ['*.raku', '*.rakumod', '*.rakudoc', '*.rakutest', '*.p6', '*.pl6', '*.pm6']
		},
		DefaultTypeDef{
			names: ['rdoc']
			globs: ['*.rdoc']
		},
		DefaultTypeDef{
			names: ['readme']
			globs: ['README*', '*README']
		},
		DefaultTypeDef{
			names: ['reasonml']
			globs: ['*.re', '*.rei']
		},
		DefaultTypeDef{
			names: ['red']
			globs: ['*.r', '*.red', '*.reds']
		},
		DefaultTypeDef{
			names: ['rescript']
			globs: ['*.res', '*.resi']
		},
		DefaultTypeDef{
			names: ['robot']
			globs: ['*.robot']
		},
		DefaultTypeDef{
			names: ['rst']
			globs: ['*.rst']
		},
		DefaultTypeDef{
			names: ['ruby']
			globs: ['config.ru', 'Gemfile', '.irbrc', 'Rakefile', '*.gemspec', '*.rb', '*.rbw', '*.rake']
		},
		DefaultTypeDef{
			names: ['rust']
			globs: ['*.rs']
		},
		DefaultTypeDef{
			names: ['sass']
			globs: ['*.sass', '*.scss']
		},
		DefaultTypeDef{
			names: ['scala']
			globs: ['*.scala', '*.sbt']
		},
		DefaultTypeDef{
			names: ['scdoc']
			globs: ['*.scd', '*.scdoc']
		},
		DefaultTypeDef{
			names: ['seed7']
			globs: ['*.sd7', '*.s7i']
		},
		DefaultTypeDef{
			names: ['sh']
			globs: ['.env', '.login', '.logout', '.profile', 'profile', '.bash_login', 'bash_login', '.bash_logout', 'bash_logout', '.bash_profile', 'bash_profile', '.bashrc', 'bashrc', '*.bashrc', '.cshrc', '*.cshrc', '.kshrc', '*.kshrc', '.tcshrc', '.zshenv', 'zshenv', '.zlogin', 'zlogin', '.zlogout', 'zlogout', '.zprofile', 'zprofile', '.zshrc', 'zshrc', '*.bash', '*.csh', '*.env', '*.ksh', '*.sh', '*.tcsh', '*.zsh']
		},
		DefaultTypeDef{
			names: ['slim']
			globs: ['*.skim', '*.slim', '*.slime']
		},
		DefaultTypeDef{
			names: ['smarty']
			globs: ['*.tpl']
		},
		DefaultTypeDef{
			names: ['sml']
			globs: ['*.sml', '*.sig']
		},
		DefaultTypeDef{
			names: ['solidity']
			globs: ['*.sol']
		},
		DefaultTypeDef{
			names: ['soy']
			globs: ['*.soy']
		},
		DefaultTypeDef{
			names: ['spark']
			globs: ['*.spark']
		},
		DefaultTypeDef{
			names: ['spec']
			globs: ['*.spec']
		},
		DefaultTypeDef{
			names: ['sql']
			globs: ['*.sql', '*.psql']
		},
		DefaultTypeDef{
			names: ['ssa']
			globs: ['*.ssa']
		},
		DefaultTypeDef{
			names: ['stylus']
			globs: ['*.styl']
		},
		DefaultTypeDef{
			names: ['sv']
			globs: ['*.v', '*.vg', '*.sv', '*.svh', '*.h']
		},
		DefaultTypeDef{
			names: ['svelte']
			globs: ['*.svelte', '*.svelte.ts']
		},
		DefaultTypeDef{
			names: ['svg']
			globs: ['*.svg']
		},
		DefaultTypeDef{
			names: ['swift']
			globs: ['*.swift']
		},
		DefaultTypeDef{
			names: ['swig']
			globs: ['*.def', '*.i']
		},
		DefaultTypeDef{
			names: ['systemd']
			globs: ['*.automount', '*.conf', '*.device', '*.link', '*.mount', '*.path', '*.scope', '*.service', '*.slice', '*.socket', '*.swap', '*.target', '*.timer']
		},
		DefaultTypeDef{
			names: ['taskpaper']
			globs: ['*.taskpaper']
		},
		DefaultTypeDef{
			names: ['tcl']
			globs: ['*.tcl']
		},
		DefaultTypeDef{
			names: ['tex']
			globs: ['*.tex', '*.ltx', '*.cls', '*.sty', '*.bib', '*.dtx', '*.ins']
		},
		DefaultTypeDef{
			names: ['texinfo']
			globs: ['*.texi']
		},
		DefaultTypeDef{
			names: ['textile']
			globs: ['*.textile']
		},
		DefaultTypeDef{
			names: ['tf']
			globs: ['*.tf', '*.tf.json', '*.tfvars', '*.tfvars.json', '*.terraformrc', 'terraform.rc', '*.tfrc', '*.terraform.lock.hcl']
		},
		DefaultTypeDef{
			names: ['thrift']
			globs: ['*.thrift']
		},
		DefaultTypeDef{
			names: ['toml']
			globs: ['*.toml', 'Cargo.lock']
		},
		DefaultTypeDef{
			names: ['ts', 'typescript']
			globs: ['*.ts', '*.tsx', '*.cts', '*.mts']
		},
		DefaultTypeDef{
			names: ['twig']
			globs: ['*.twig']
		},
		DefaultTypeDef{
			names: ['txt']
			globs: ['*.txt']
		},
		DefaultTypeDef{
			names: ['typoscript']
			globs: ['*.typoscript', '*.ts']
		},
		DefaultTypeDef{
			names: ['typst']
			globs: ['*.typ']
		},
		DefaultTypeDef{
			names: ['usd']
			globs: ['*.usd', '*.usda', '*.usdc']
		},
		DefaultTypeDef{
			names: ['v']
			globs: ['*.v', '*.vsh']
		},
		DefaultTypeDef{
			names: ['vala']
			globs: ['*.vala']
		},
		DefaultTypeDef{
			names: ['vb']
			globs: ['*.vb']
		},
		DefaultTypeDef{
			names: ['vcl']
			globs: ['*.vcl']
		},
		DefaultTypeDef{
			names: ['verilog']
			globs: ['*.v', '*.vh', '*.sv', '*.svh']
		},
		DefaultTypeDef{
			names: ['vhdl']
			globs: ['*.vhd', '*.vhdl']
		},
		DefaultTypeDef{
			names: ['vim']
			globs: ['*.vim', '.vimrc', '.gvimrc', 'vimrc', 'gvimrc', '_vimrc', '_gvimrc']
		},
		DefaultTypeDef{
			names: ['vimscript']
			globs: ['*.vim', '.vimrc', '.gvimrc', 'vimrc', 'gvimrc', '_vimrc', '_gvimrc']
		},
		DefaultTypeDef{
			names: ['vue']
			globs: ['*.vue']
		},
		DefaultTypeDef{
			names: ['webidl']
			globs: ['*.idl', '*.webidl', '*.widl']
		},
		DefaultTypeDef{
			names: ['wgsl']
			globs: ['*.wgsl']
		},
		DefaultTypeDef{
			names: ['wiki']
			globs: ['*.mediawiki', '*.wiki']
		},
		DefaultTypeDef{
			names: ['xml']
			globs: ['*.xml', '*.xml.dist', '*.dtd', '*.xsl', '*.xslt', '*.xsd', '*.xjb', '*.rng', '*.sch', '*.xhtml']
		},
		DefaultTypeDef{
			names: ['xz']
			globs: ['*.xz', '*.txz']
		},
		DefaultTypeDef{
			names: ['yacc']
			globs: ['*.y']
		},
		DefaultTypeDef{
			names: ['yaml']
			globs: ['*.yaml', '*.yml']
		},
		DefaultTypeDef{
			names: ['yang']
			globs: ['*.yang']
		},
		DefaultTypeDef{
			names: ['z']
			globs: ['*.Z']
		},
		DefaultTypeDef{
			names: ['zig']
			globs: ['*.zig']
		},
		DefaultTypeDef{
			names: ['zsh']
			globs: ['.zshenv', 'zshenv', '.zlogin', 'zlogin', '.zlogout', 'zlogout', '.zprofile', 'zprofile', '.zshrc', 'zshrc', '*.zsh']
		},
		DefaultTypeDef{
			names: ['zstd']
			globs: ['*.zst', '*.zstd']
		},
	]
}
