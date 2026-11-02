# Upstreams

`external/wine` and `external/dxmt` are OmniTroid forks; this records what each fork's `main` is built on.

| Submodule | Upstream | In `main` | Checked |
|---|---|---|---|
| `external/wine` | [CodeWeavers' CrossOver sources](https://www.codeweavers.com/crossover/source) | `crossover-sources-26.3.0.tar.gz` (tag `crossover-26.3.0`) | 2026-10-30, newest published |
| `external/dxmt` | [dttdrv/mullion](https://github.com/dttdrv/mullion) `main`, for D3D10 to 12, the shader converter, the core and winemetal | `992fc9e` (2026-11-02), import commit `cfbff640`; left out: the NGX signing certificate and its trust | 2026-11-02, newest |
| `external/dxmt` | [3Shain/dxmt](https://github.com/3Shain/dxmt) `main`, its base at `7c8dee1`; reviewed up to `647b002`, and what the tree lacked ported by hand; its DXIL front end is not used | | 2026-11-02 |

Both forks also carry patches from [Highball](https://github.com/gauthierpiarrette/highball) and our own, as commits on top.

## Updating

Bring upstream into a branch of the fork, test it, merge the PR, then bump the pin in Neutron (`git add external/<name>`) and update the table above.

DXMT: clone the upstream into a temporary directory, rename it to DXMT's names, and compare it with what was last taken from it. Port the changes worth having as ordinary commits. No upstream stays as a remote or branch of the fork.

```sh
cd external/dxmt
tmp=$(mktemp -d)
git clone https://github.com/dttdrv/mullion.git "$tmp/upstream"
git -C "$tmp/upstream" log --oneline 992fc9e..HEAD    # the table's commit
rm -rf "$tmp/upstream/.git"
(cd "$tmp/upstream"
 grep -rIl -i mullion . | xargs perl -pi -e 's#dttdrv/mullion#OmniTroid/dxmt#g; s/mullion/dxmt/g; s/Mullion/DXMT/g; s/MULLION/DXMT/g'
 find . -depth -iname '*mullion*' | while read -r f; do mv "$f" "$(dirname "$f")/$(basename "$f" | perl -pe 's/mullion/dxmt/g; s/Mullion/DXMT/g; s/MULLION/DXMT/g')"; done)
mkdir "$tmp/base" && git archive cfbff640 | tar -x -C "$tmp/base"
git diff --no-index --stat "$tmp/base" "$tmp/upstream"
git switch -c upstream-$(date +%Y%m%d) origin/main
```

Test the ported commits with `tests/d3d9/run.sh <wine-install>`, open a PR with `gh pr create --base main`, and remove `$tmp`. Compare `3Shain/dxmt` the same way, from the commit in the table.

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
