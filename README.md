# Mathport

Mathport is a tool for porting Lean3 projects to Lean4. It consists of two (loosely coupled) components:

- "binport", which translates Lean3 `.lean` files to Lean4 `.olean` files
- "synport", which best-effort translates Lean3 `.lean` files to Lean4 `.lean` files

## Running on mathlib

If you want to port a file from mathlib to mathlib4, you don't need anything here.
Instead you should go to the mathlib4 repository, and use `scripts/start_port.sh`.

## Running on a single file

Mathport supports a "oneshot" mode, for porting individual files or quick tests.
A template is set up in the `Oneshot/` directory. See [`Oneshot/README.md`](Oneshot/README.md).

## Running on a project other than mathlib

Install dependencies if needed:

- debian/ubuntu: `sudo apt install cmake gmp gmp-devel jq`
- mac: `brew install cmake jq`

In the mathport folder:

- `lake exe cache get`
- `make build`
  This step is somewhat expensive as we need to compile (not just build)
  all of the dependencies of tactics.
- `make source`

Next, you'll need to prepare your project.

If it is possible to bump your mathlib dependency to the latest mathlib3,
mathport will have a better chance.
If you really want to run against an older mathlib3 (good luck!):

- In `sources/mathlib` run `git --fetch unshallow`
- `git checkout SHA`
- `leanproject get-cache`

It is probably best to clone a fresh copy for this
(outside of the `mathport` directory).

- In `leanpkg.path`, change the line `path _target/deps/mathlib/src` to
  `path [path-mathport]/sources/mathlib/src`
- In your project, run `leanproject mk-all`.
- In your project, run `lean --make --recursive --ast --tlean src`.

Now, in mathport, edit `config-project.json` as follows:

- Under `pathConfig/packages/`, change the string after the `"Project"` key
  to the relative path from the mathport directory to your
  external project's `src/` directory.

Then run

- `./download-release.sh`
  (Or `./download-release.sh [relevant-release]`
  if you are running against an old mathlib;
  see [mathport releases](https://github.com/leanprover-community/mathport/releases),
  and find the nearest `nightly`.)
- `./build/bin/mathport --make config-project.json Project::all`

If it succeeds, you should find Lean4 lean files in `Outputs/src/project/`.
(Note this may be hidden in the VS Code explorer,
but you can open it in the terminal.)

If you need to re-run mathport, you will need to `rm -rf Outputs/olean/project`.

If the generated Lean files look plausible,
you will want to move them into a new Lean 4 project.

Somewhere outside of the `mathport` folder, run
`lake +leanprover/lean4:nightly-2023-05-22 init MyProject math`
(probably updating `nightly-2023-05-22`
to match the toolchain in current `mathlib4`).
Then you can `mv Outputs/src/project/Project ../MyProject/MyProject`,
and then inside `MyProject` run `lake update` and `lake exe cache get`.

After that you should be able to edit files in VS Code,
and begin fixing remaining errors.

You will need to edit the imports to change
`import Mathbin.XYZ` to `import Mathlib.XYZ`.

Please expect errors if any of your filenames require escaping via `«...»`.
(In particular if your filenames start with numerals.)

## Running with artifacts from continuous integration

A full run of `mathport` (see below) on Lean 3 and mathlib3 takes several hours.
We provide artifacts on the github releases page,
and separate repositories
containing the `.lean` files and `.olean` files generated from Lean 3 and from mathlib3.

Please use the repositories
https://github.com/leanprover-community/lean3port
and
https://github.com/leanprover-community/mathlib3port
and run `lake exe cache get` and then
`lake build` to obtain the generated `.olean` files.

Using these repositories, you can open the synported `.lean` files in VS Code
to see the current state of output.

Alternatively, you can import some or all of the binported `.olean` files
using e.g.

```lean
import Mathbin.AlgebraicGeometry.Scheme

#lookup3 algebraic_geometry.Scheme
#check AlgebraicGeometry.Scheme
```

(Specifying the `mathlib3port` repository as a Lake dependency in your own
project should work to enable `import Mathbin.All`.)

Update 2022-10-21: The above binport configuration is no longer supported by default.
The olean files generated by the nightlies now prioritize using the user specified alignments
over type-correctness, so many mathlib theorems will be broken or stubbed. The old behavior
can be recovered by setting `"skipDefEq": false` in the `config.json`, but you will have to
run mathport yourself (see below) rather than downloading the pre-built artifacts
created by `make port`.

The synported `.lean` files are checked in to these repositories:
feel free to commit new versions
if you have updated the dependencies in the relevant lakefile
and downloaded fresh `.lean` files using the `update.sh <tag>` script,
where `<tag>` is a release from https://github.com/leanprover-community/mathport/releases

## Running mathport locally

See the `Makefile` for usage (it takes several hours to rebuild the mathlib3 port from scratch).
Basic usage is `lake exe cache get` and then `make build source predata port`.

We provide artifacts for various stages of the build on the releases page of the `mathport` repository.
The script `./download-release.sh nightly-YYYY-MM-DD` downloads one of these,
after which you can skip the `make predata` and/or `make port` steps
(you will still need to run `make build` and `make source`).

The script `./download-release.sh` separately calls
`download-predata.sh` and `download-ported.sh`.
We run CI for predata more frequently.

To port a single file execute `mathport` as follows
(depending on whether you want to port a core or a mathlib file):
```
./build/bin/mathport config.json Leanbin::init.data.nat.gcd
./build/bin/mathport config.json Mathbin::field_theory.abel_ruffini
```

The directory `Test` contains subdirectories `importLeanBin` and `importMathbin`,
each containing a `lakefile.lean` that depends on `lean3port` and `mathlib3port`, resp.
