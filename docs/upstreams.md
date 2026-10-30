# Upstreams

`external/wine` and `external/dxmt` are OmniTroid forks; this records what each fork's `main` is built on.

| Submodule | Upstream | In `main` | Checked |
|---|---|---|---|
| `external/wine` | [CodeWeavers' CrossOver sources](https://www.codeweavers.com/crossover/source) | `crossover-sources-26.3.0.tar.gz` (tag `crossover-26.3.0`) | 2026-10-30, newest published |
| `external/dxmt` | [3Shain/dxmt](https://github.com/3Shain/dxmt) `main` | `3b25259` (2026-10-27) | 2026-10-30, newest |

Both forks also carry patches from [Highball](https://github.com/gauthierpiarrette/highball) and our own, as commits on top.

## Updating

Bring upstream into a branch of the fork, test it, merge the PR, then bump the pin in Neutron (`git add external/<name>`) and update the table above.

DXMT:

```sh
cd external/dxmt
git remote add upstream https://github.com/3Shain/dxmt.git   # once
git fetch upstream && git switch -c upstream-$(date +%Y%m%d) origin/main && git merge upstream/main
tests/d3d9/run.sh <wine-install>
git push origin HEAD && gh pr create --base main
```

Wine: each CrossOver release is imported as one commit on the `crossover` branch, whose tree is the tarball's `sources/` directory.

```sh
cd external/wine
git switch crossover
curl -LO https://media.codeweavers.com/pub/crossover/source/crossover-sources-<version>.tar.gz
git rm -rq . && tar -xzf crossover-sources-<version>.tar.gz --strip-components 1 && rm crossover-sources-<version>.tar.gz
git add -A && git commit -m "Import CrossOver <version> sources" && git tag crossover-<version>
git push origin crossover crossover-<version>
git switch -c crossover-<version> origin/main && git merge crossover
git push origin HEAD && gh pr create --base main
```
