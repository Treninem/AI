class_name CodeLanguageRegistry
extends RefCounted

var languages: Dictionary = {
	"gdscript": {"extensions":["gd"], "family":"Godot", "build":"godot --headless --path . --quit", "test":"godot --headless --path . --quit-after 1"},
	"python": {"extensions":["py","pyw"], "family":"Python", "build":"python -m py_compile <file>", "test":"pytest -q"},
	"javascript": {"extensions":["js","mjs","cjs"], "family":"JavaScript", "build":"node --check <file>", "test":"npm test"},
	"typescript": {"extensions":["ts","tsx","mts","cts"], "family":"TypeScript", "build":"tsc --noEmit", "test":"npm test"},
	"c": {"extensions":["c","h"], "family":"C/C++", "build":"gcc <file> -o app", "test":"project-specific"},
	"cpp": {"extensions":["cpp","cc","cxx","hpp","hh","hxx"], "family":"C/C++", "build":"g++ <file> -o app", "test":"project-specific"},
	"csharp": {"extensions":["cs","csproj","sln"], "family":".NET", "build":"dotnet build", "test":"dotnet test"},
	"java": {"extensions":["java","gradle","gradle.kts"], "family":"JVM", "build":"javac / Gradle / Maven", "test":"gradle test / mvn test"},
	"kotlin": {"extensions":["kt","kts"], "family":"JVM", "build":"kotlinc / Gradle", "test":"gradle test"},
	"rust": {"extensions":["rs","toml"], "family":"Rust", "build":"cargo build", "test":"cargo test"},
	"go": {"extensions":["go","mod","sum"], "family":"Go", "build":"go build ./...", "test":"go test ./..."},
	"php": {"extensions":["php"], "family":"PHP", "build":"php -l <file>", "test":"phpunit"},
	"ruby": {"extensions":["rb","gemspec"], "family":"Ruby", "build":"ruby -c <file>", "test":"bundle exec rspec"},
	"lua": {"extensions":["lua"], "family":"Lua", "build":"luac -p <file>", "test":"busted"},
	"swift": {"extensions":["swift"], "family":"Swift", "build":"swift build", "test":"swift test"},
	"dart": {"extensions":["dart"], "family":"Dart/Flutter", "build":"dart analyze / flutter analyze", "test":"dart test / flutter test"},
	"sql": {"extensions":["sql"], "family":"SQL", "build":"dialect-specific validation", "test":"migration/test database"},
	"html": {"extensions":["html","htm"], "family":"Web", "build":"validator/bundler", "test":"browser tests"},
	"css": {"extensions":["css","scss","sass","less"], "family":"Web", "build":"stylelint / bundler", "test":"visual tests"},
	"shell": {"extensions":["sh","bash","zsh"], "family":"Shell", "build":"bash -n <file>", "test":"shellcheck / bats"},
	"powershell": {"extensions":["ps1","psm1","psd1"], "family":"PowerShell", "build":"PowerShell parser", "test":"Pester"},
	"r": {"extensions":["r","rmd"], "family":"R", "build":"Rscript", "test":"testthat"},
	"julia": {"extensions":["jl"], "family":"Julia", "build":"julia <file>", "test":"Pkg.test()"},
	"elixir": {"extensions":["ex","exs"], "family":"BEAM", "build":"mix compile", "test":"mix test"},
	"erlang": {"extensions":["erl","hrl"], "family":"BEAM", "build":"erlc <file>", "test":"rebar3 eunit"},
	"haskell": {"extensions":["hs","lhs"], "family":"Haskell", "build":"ghc / cabal / stack", "test":"cabal test / stack test"},
	"ocaml": {"extensions":["ml","mli"], "family":"OCaml", "build":"dune build", "test":"dune runtest"},
	"zig": {"extensions":["zig"], "family":"Zig", "build":"zig build", "test":"zig build test"},
	"nim": {"extensions":["nim","nims"], "family":"Nim", "build":"nim c <file>", "test":"nimble test"},
	"crystal": {"extensions":["cr"], "family":"Crystal", "build":"crystal build <file>", "test":"crystal spec"},
	"fortran": {"extensions":["f","f90","f95","f03","f08"], "family":"Fortran", "build":"gfortran <file> -o app", "test":"project-specific"},
	"cobol": {"extensions":["cob","cbl","cpy"], "family":"COBOL", "build":"cobc", "test":"project-specific"},
	"pascal": {"extensions":["pas","pp","lpr"], "family":"Pascal", "build":"fpc <file>", "test":"project-specific"},
	"assembly": {"extensions":["asm","s","S"], "family":"Assembly", "build":"nasm/gas + linker", "test":"architecture-specific"},
	"scala": {"extensions":["scala","sbt"], "family":"JVM", "build":"sbt compile", "test":"sbt test"},
	"clojure": {"extensions":["clj","cljs","cljc","edn"], "family":"JVM", "build":"clojure tools / lein", "test":"project-specific"},
	"groovy": {"extensions":["groovy","gvy","gy","gsh"], "family":"JVM", "build":"groovyc", "test":"Gradle/Spock"},
	"perl": {"extensions":["pl","pm","t"], "family":"Perl", "build":"perl -c <file>", "test":"prove"},
	"objective-c": {"extensions":["m","mm"], "family":"Apple", "build":"clang / xcodebuild", "test":"xcodebuild test"},
	"solidity": {"extensions":["sol"], "family":"EVM", "build":"solc / forge build", "test":"forge test / hardhat test"},
	"v": {"extensions":["v"], "family":"V", "build":"v <file>", "test":"v test ."},
	"racket": {"extensions":["rkt","rktl"], "family":"Lisp", "build":"raco make", "test":"raco test"},
	"common-lisp": {"extensions":["lisp","lsp","cl"], "family":"Lisp", "build":"implementation-specific", "test":"FiveAM / project-specific"},
	"prolog": {"extensions":["pro","prolog","plg"], "family":"Logic", "build":"SWI-Prolog", "test":"plunit"},
	"matlab": {"extensions":["m"], "family":"MATLAB/Octave", "build":"matlab/octave", "test":"matlab.unittest"},
	"vue": {"extensions":["vue"], "family":"Web", "build":"npm run build", "test":"npm test"},
	"svelte": {"extensions":["svelte"], "family":"Web", "build":"npm run build", "test":"npm test"},
}

func detect_from_path(path: String) -> String:
	var file := path.get_file().to_lower()
	if file == "cargo.toml": return "rust"
	if file == "go.mod": return "go"
	if file == "package.json": return "javascript"
	if file == "project.godot": return "gdscript"
	var ext := path.get_extension().to_lower()
	for language in languages.keys():
		if ext in languages[language]["extensions"]:
			return str(language)
	return "unknown"

func describe(language: String) -> Dictionary:
	return languages.get(language.to_lower(), {"family":"Unknown", "extensions":[], "build":"detect from project", "test":"detect from project"})

func all_languages() -> Array:
	var out: Array = languages.keys()
	out.sort()
	return out
