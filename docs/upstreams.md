# Upstreams

`external/wine` and `external/dxmt` are OmniTroid forks; this records what each fork's `main` is built on.

| Submodule | Upstream | In `main` | Checked |
|---|---|---|---|
| `external/wine` | [CodeWeavers' CrossOver sources](https://www.codeweavers.com/crossover/source) | `crossover-sources-26.3.0.tar.gz` (tag `crossover-26.3.0`) | 2026-10-30, newest published |
| `external/dxmt` | [dttdrv/mullion](https://github.com/dttdrv/mullion) `main`, for D3D10 to 12, the shader converter, the core and winemetal | `695dbe2a` (2026-10-30), import commit `aaff4fdd` on branch `d3d12-import` | 2026-10-30, newest |
| `external/dxmt` | [3Shain/dxmt](https://github.com/3Shain/dxmt) `main`, its base at `7c8dee1` (2026-09-16); merged up to `3b25259`, but the import's code won wherever both changed | | 2026-10-30 |

Both forks also carry patches from [Highball](https://github.com/gauthierpiarrette/highball) and our own, as commits on top.

## Updating

Bring upstream into a branch of the fork, test it, merge the PR, then bump the pin in Neutron (`git add external/<name>`) and update the table above.

DXMT: each import is one commit on `d3d12-import`, the upstream tree renamed to DXMT's names.

```sh
cd external/dxmt
git remote add dttdrv https://github.com/dttdrv/mullion.git   # once
git fetch dttdrv
mkdir import && git archive dttdrv/main | tar -x -C import
cd import
grep -rIl -i mullion . | xargs perl -pi -e 's#dttdrv/mullion#OmniTroid/dxmt#g; s/mullion/dxmt/g; s/Mullion/DXMT/g; s/MULLION/DXMT/g'
find . -depth -iname '*mullion*' -execdir sh -c 'mv "$1" "$(echo "$1" | perl -pe "s/mullion/dxmt/g; s/Mullion/DXMT/g; s/MULLION/DXMT/g")"' _ {} \;
cd ..
export GIT_INDEX_FILE=$PWD/import.index
git read-tree dttdrv/main && GIT_WORK_TREE=import git add -A . && tree=$(git write-tree)
unset GIT_INDEX_FILE
git branch -f d3d12-import "$(git commit-tree "$tree" -p d3d12-import -m "Import dttdrv/mullion $(git rev-parse --short dttdrv/main)")"
git switch -c import-$(date +%Y%m%d) origin/main && git merge d3d12-import
tests/d3d9/run.sh <wine-install>
git push origin d3d12-import HEAD && gh pr create --base main
```

3Shain's newer commits come through that upstream, or by `git cherry-pick` of the ones it lacks.

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
