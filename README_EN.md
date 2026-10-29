# DeepSeek Harness Offline Installer

A one-shot, fully offline deployment package for the **DeepSeek Harness web UI** on **Kylin V10 Desktop (arm64)** intranets.

- **No network required** — Node.js, dsh, pnpm, and the Python environment are bundled; the installer never reaches the internet.
- **No sudo required** — everything is installed under the current user's home directory.
- **Ready out of the box** — a "DeepSeek Harness" desktop icon appears after installation; double-click it to start the service and open the browser.
- **Python 3.11 included** — document, data-science, plotting, and database libraries are preinstalled and ready to use.

| Component | Version |
| --- | --- |
| Node.js | v26.2.0 (linux-arm64) |
| dsh (`@deepseek-ai/dsh`) | 0.2.1-rc.2 |
| pnpm | 12.16.1 |
| Python | 3.11.16 (uv-managed, independent of the system Python) |

> See [ROADMAP.md](ROADMAP.md) for planned work (multi-architecture packages, auto-detection).

---

## 1. Package Contents

| File | Size | Purpose |
| --- | --- | --- |
| `deepseek-harness-user-offline.tar.gz` | ~760 MB | Self-contained runtime (expands to ~2.7 GB): Node.js + dsh + pnpm + Python 3.11 environment + desktop icon |
| `install-on-target.sh` | 6 KB | Installer to run on the **target machine** (no sudo) |
| `make-offline.sh` | 15 KB | Rebuilds the offline package on an **internet-connected build machine** |
| `node-v26.2.0-linux-arm64.tar.xz` | 31 MB | Official Node.js prebuilt binary; only needed when rebuilding, not on the target |
| `uv-aarch64-unknown-linux-gnu.tar.gz` | 18 MB | Standalone uv binary used to build the Python 3.11 environment; only needed when rebuilding |
| `icon.jpeg` | 5 KB | Desktop launcher icon |
| `README.md` / `README_EN.md` | — | Chinese / English documentation |

> The target machine only needs **`deepseek-harness-user-offline.tar.gz` + `install-on-target.sh`**; the remaining files can stay on the build machine.

---

## 2. Requirements

- OS: Kylin V10 (`aarch64`), glibc ≥ 2.28 (V10 ships 2.31, which is sufficient).
- Disk space: about 2.7 GB for the install directory (Node/dsh ~1.4 GB + Python runtime ~95 MB + preinstalled packages ~1.2 GB); allow ~4 GB while copying and extracting.
- Privileges: a regular user account; **no root or sudo**.
- Desktop: any environment supporting `.desktop` entries (GNOME, MATE, UKUI, …).

> **x86_64 machines**: this package bundles arm64 Node.js and cannot run on x86_64. Rebuild it with `ARCH="x64"` as described in [section 7](#7-rebuilding-on-an-internet-connected-machine).

---

## 3. Quick Start (Target Machine)

### 3.1 Copy the files

Copy `deepseek-harness-user-offline.tar.gz` and `install-on-target.sh` into the **same directory** on the Kylin machine, e.g. `~/Downloads/dsh-offline/`.

### 3.2 Run the installer

```bash
cd ~/Downloads/dsh-offline       # required: the script looks for the tarball by relative path
bash install-on-target.sh
```

When you see `✓ 安装完成。` ("installation complete"), it worked. The process usually takes 2–5 minutes, mostly spent extracting the ~2.7 GB runtime.

### 3.3 Start

- **Recommended**: double-click the **"DeepSeek Harness"** desktop icon.
- Or from a terminal:

```bash
dsh-web        # equivalent to dsh web; extra arguments are forwarded as-is
```

A terminal window opens and tells you **not to close it**. The browser then opens automatically at:

```
http://127.0.0.1:3080
```

> That terminal window hosts the dsh service. Closing it or pressing `Ctrl+C` stops the service and the browser loses access.

### 3.4 Configure a model

1. Open **Settings → Models**.
2. Add a **Custom Provider**.
3. Enter your intranet OpenAI-compatible endpoint (for example `http://10.0.0.5:8000/v1`), the API key, and the model name.
4. Save, then select the model in a chat session.

---

## 4. What the Installer Does

The installer only touches the current user's home directory:

| Action | Location |
| --- | --- |
| Extract the runtime (dropping the top-level directory) | `~/.local/opt/deepseek-harness/` |
| Create `dsh` / `node` / `pnpm` command symlinks | `~/.local/bin/` |
| Install global npm packages: dsh, pnpm, `pptxgenjs@3.12.0` | `~/.local/opt/deepseek-harness/node/lib/node_modules/` |
| Append `~/.local/bin` to `PATH` if missing | `~/.profile` |
| Initialize the web profile and add required offline pnpm settings | `~/.dsh/profiles/web/pnpm-workspace.yaml` |
| Fix Python environment paths and create `dsh-python` / `dsh-pip` | `~/.local/opt/deepseek-harness/python-venv/`, `~/.local/bin/` |
| Generate the launcher (prints a notice, then runs `dsh web`) | `~/.local/bin/dsh-web` |
| Install the desktop icon | `~/.local/share/icons/deepseek-harness.jpeg` |
| Create and trust the desktop shortcut | `~/桌面/dsh-web.desktop` (or `~/Desktop/` when no localized desktop directory exists) |

Two settings are appended to `pnpm-workspace.yaml` so that **plugins can be installed offline**:

```yaml
minimumReleaseAge: 0            # disables pnpm>=11 supply-chain delay checks
dangerouslyAllowAllBuilds: true # allows plugin build scripts
```

Resulting layout:

```
~/.local/opt/deepseek-harness/
├── node/                     # Node.js runtime
│   ├── bin/{node,npm,npx,pnpm,dsh}
│   └── lib/node_modules/     # global packages: @deepseek-ai/dsh, pnpm
├── python/                   # uv-managed Python 3.11 runtime
├── python-venv/              # virtual environment with all packages preinstalled
│   └── PYTHON_ENV.txt        # build time, Python/uv versions, pip freeze
├── python-requirements.txt   # readable dependency list (generated during build)
├── uv/                       # bundled uv (reusable)
└── dsh-web-icon.jpeg         # desktop icon source

~/.local/bin/dsh-web          # launcher
~/.local/bin/dsh-python       # wrapper: always uses the venv Python 3.11
~/.local/bin/dsh-pip          # wrapper: pip for that venv
~/.dsh/                       # user data and config (kept outside the package; survives upgrades)
```

### Python 3.11 environment

The bundle includes a self-contained Python 3.11.16 runtime managed by [uv](https://github.com/astral-sh/uv) under `python/`; it does not replace or affect the system Python. The `python-venv/` environment comes with the following packages preinstalled (installed in a single `uv pip install`):

| Category | Packages |
| --- | --- |
| Documents / Office | `markitdown[pptx]` `Pillow` `defusedxml` `lxml` `python-pptx` `python-docx` `openpyxl` `xlrd` `xlsxwriter` `python-calamine` `olefile` `PyMuPDF` `pdfplumber` `pytesseract` `pypandoc` `docxtpl` |
| Data / scientific | `pandas` `numpy` `scipy` `chardet` `python-magic` `xlsx2csv` `unstructured` `matplotlib` `seaborn` `plotly` `kaleido` `pygame` |
| Diagrams / mind maps | `graphviz` `pygraphviz` `diagrams` `networkx` `xmind` `xmindparser` |
| Databases | `psycopg2-binary` `pymongo` `redis` `sqlalchemy` `pymysql` `sqlcipher3` `oracledb` `dmPython` (optional; a failure does not abort the build) |
| Web / geodesy | `Flask` `geographiclib` |
| Utilities | `requests` `pyyaml` `jinja2` `tabulate` `tqdm` |

The Node side also has `pptxgenjs@3.12.0` installed globally (PPTX generation, unrelated to Python); `dsh-web` sets `NODE_PATH`, so `node -e "require('pptxgenjs')"` works in dsh terminals.

Usage:

```bash
dsh-python -V                    # Python 3.11.16
dsh-python -m pip list           # list installed packages
dsh-python your_script.py        # run a script
dsh-pip install <package>        # only works with an internal PyPI mirror

# or activate the environment (optional when using dsh web manually)
source ~/.local/opt/deepseek-harness/python-venv/bin/activate
```

**Using it inside dsh requires no activation.** The `dsh-web` launcher puts `python-venv/bin` at the front of `PATH`, so `python`, `pip`, and `python3` in dsh's terminal tool are already the bundled 3.11 environment; agents can also call `dsh-python` directly. To keep the system Python instead, start with `DSH_NO_PYTHON_PATH=1`. Running `dsh web` directly (bypassing `dsh-web`) does not inject the venv; activate it first or use `dsh-python`.
- `python/` and `python-venv/` are built with `--relocatable`; the installer rewrites the venv's `pyvenv.cfg` and interpreter link on the target, so a different username or home directory is fine.
- **Rendering** with `pytesseract`, `pypandoc`, or `graphviz`/`diagrams` still needs the system executables `tesseract`, `pandoc`, and `dot` (Graphviz). They are not pip packages and must be installed separately; the Python APIs work without them.
- The environment is fully offline; `dsh-pip install` cannot reach the public internet by default. To add packages, set up an internal PyPI mirror or pre-download the wheels.

---

## 5. Day-to-Day Usage

```bash
dsh-web                              # start the web service and open the browser
dsh web                              # underlying command (dsh-web wraps this)
dsh --version                        # show version
dsh --profile web --dump-config      # show the composed web-profile config
```

- The service listens on `127.0.0.1:3080` and is reachable from this machine only.
- Sessions, configuration, and plugins live in `~/.dsh/`. Deleting the install directory keeps your data; deleting `~/.dsh/` wipes all configuration.
- In an offline network the public plugin registry is unreachable. To install plugins, publish the tarballs to an internal registry or a local directory first, then install them with pnpm.

---

## 6. Upgrade and Uninstall

### Upgrade

Run `install-on-target.sh` again with the new `deepseek-harness-user-offline.tar.gz`. The runtime under `~/.local/opt/deepseek-harness/` is replaced, while **user data in `~/.dsh/` is left untouched**.

### Uninstall

```bash
# 1. Remove the runtime and commands
rm -rf ~/.local/opt/deepseek-harness
rm -f  ~/.local/bin/dsh ~/.local/bin/node ~/.local/bin/pnpm ~/.local/bin/dsh-web
rm -f  ~/.local/bin/dsh-python ~/.local/bin/dsh-pip

# 2. Remove the desktop shortcut and icon
rm -f  ~/桌面/dsh-web.desktop ~/Desktop/dsh-web.desktop
rm -f  ~/.local/share/icons/deepseek-harness.jpeg

# 3. Only if you no longer need personal data (sessions, config, plugins):
# rm -rf ~/.dsh
```

The `PATH` line appended to `~/.profile` may be left in place; it is harmless.

---

## 7. Rebuilding on an Internet-Connected Machine

Use this to upgrade versions, switch architectures (arm64 → x64), or use a different internal mirror.

### Prerequisites

1. A Linux build machine with the **same architecture as the target** and internet access.
2. `npm`, `tar`, and `xz` available.
3. The official Node.js prebuilt archive, e.g. `node-v26.2.0-linux-arm64.tar.xz` ([download](https://nodejs.org/dist/v26.2.0/)).
4. The standalone uv archive, e.g. `uv-aarch64-unknown-linux-gnu.tar.gz` ([download](https://github.com/astral-sh/uv/releases)); skip this if `uv` is already installed on the build machine.
5. `icon.jpeg` in the same directory as the script.
6. Access to a PyPI mirror (the Tsinghua mirror is the default; override with `PIP_INDEX_URL`).

### Build

```bash
# Change the architecture if needed: arm64 / x64
sed -i 's/^ARCH=.*/ARCH="x64"/' make-offline.sh

# Optional: use a different PyPI mirror
export PIP_INDEX_URL=https://pypi.tuna.tsinghua.edu.cn/simple

bash make-offline.sh
```

The script deploys Node.js → installs `@deepseek-ai/dsh`, `pnpm`, and `pptxgenjs` globally → installs a standalone Python 3.11 via uv and creates a relocatable venv → **installs all Python packages in one merged `uv pip install`** → runs Python and web smoke tests → regenerates `install-on-target.sh` → produces `deepseek-harness-user-offline.tar.gz`.

> ⚠️ **Caution**: the build script installs the runtime into the **current user's** `~/.local/opt/deepseek-harness`, overwriting any previous build there. The smoke test uses a temporary `DSH_HOME` and does not touch your `~/.dsh`. A clean build machine (or dedicated container) is still recommended.
>
> The extracted Python environment is about 1.3 GB. Building needs 3–4 GB of extra temporary space and downloads several hundred MB of wheels from PyPI; allow 15–30 minutes for the first build.

Then copy the new `deepseek-harness-user-offline.tar.gz` and `install-on-target.sh` to the target machine.

---

## 8. Troubleshooting

**Double-clicking the desktop icon does nothing**

```bash
chmod +x ~/桌面/dsh-web.desktop
gio set ~/桌面/dsh-web.desktop metadata::trusted true
```

Some desktops also require right-clicking the icon and choosing "Allow Launching".

**`dsh: command not found`**

`~/.local/bin` is not on your `PATH`. Log in again, or run:

```bash
source ~/.profile
# or temporarily:
export PATH="$HOME/.local/bin:$PATH"
```

**`dsh-python: command not found`**

Check that `~/.local/bin` is on your `PATH`. If the file does not exist, the installer did not find the bundled Python runtime; re-run `install-on-target.sh`. You can also use the absolute path:

```bash
~/.local/opt/deepseek-harness/python-venv/bin/python -V
```

**Python fails with `No module named 'encodings'` or a venv path error**

The install directory was moved, or the archive was extracted without `install-on-target.sh`. Re-run the installer, which rewrites `pyvenv.cfg` and the interpreter link:

```bash
bash install-on-target.sh
```

**matplotlib complains about a read-only config directory**

If the home directory is write-restricted, point the cache elsewhere:

```bash
export MPLCONFIGDIR="$HOME/.cache/matplotlib"
```

**`pytesseract` / `pypandoc` / `graphviz` cannot find an executable at runtime**

These libraries are only Python wrappers; install `tesseract`, `pandoc`, and `dot` (Graphviz) system packages on the target. For offline machines, use the corresponding RPM/DEB packages.

**`dsh-pip install` cannot reach the network**

This is expected: the package has no public internet access. Configure an internal PyPI mirror (`PIP_INDEX_URL`), or pre-download wheels and use `dsh-pip install --no-index --find-links <dir>`.

**pnpm blocks installs with `minimumReleaseAge` or refuses build scripts**

Check that `~/.dsh/profiles/web/pnpm-workspace.yaml` contains:

```yaml
minimumReleaseAge: 0
dangerouslyAllowAllBuilds: true
```

Add the lines manually and restart `dsh-web` if they are missing.

**Port 3080 is already in use**

```bash
ss -ltnp | grep 3080
# Stop the process, or run on another port for now:
dsh --profile web --port 3081
# The launcher forwards arguments too:
dsh-web --port 3081
```

**Startup fails with `Exec format error` / `cannot execute binary file`**

The target architecture does not match the bundled Node.js (for example, an arm64 package on an x86_64 machine). Rebuild with `ARCH="x64"` as described in section 7.

**Startup fails with `GLIBC_2.28 not found`**

The system glibc is too old for the official Node.js prebuilt binaries. Upgrade the OS, or use a self-compiled Node.js.

**The browser does not open automatically**

Open <http://127.0.0.1:3080> manually. On headless systems or without a default browser, nothing is launched automatically.

**The desktop icon shows a generic placeholder**

The icon file is missing or unreadable. Verify that `~/.local/share/icons/deepseek-harness.jpeg` exists, or re-run the installer.

**First start is slow**

The first launch initializes the profile and plugin directories; this usually takes 10–30 seconds and subsequent starts are noticeably faster.

---

## 9. Security Notes

- The service listens on loopback (`127.0.0.1`) only. Do not forward or expose it to untrusted networks.
- The package contains official Node.js prebuilt binaries, a standalone Python runtime, and public npm/PyPI packages. Verify integrity with `sha256sum` before and after copying.
- The installer never runs `sudo` and never writes to system directories; every change can be reverted with the commands in section 6.
