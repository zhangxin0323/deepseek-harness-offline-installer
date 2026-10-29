# DeepSeek Harness Offline Installer

A one-shot, fully offline deployment package for the **DeepSeek Harness web UI** on **Kylin V10 Desktop (arm64)** intranets.

- **No network required** — Node.js, dsh, and pnpm are bundled; the installer never reaches the internet.
- **No sudo required** — everything is installed under the current user's home directory.
- **Ready out of the box** — a "DeepSeek Harness" desktop icon appears after installation; double-click it to start the service and open the browser.

| Component | Version |
| --- | --- |
| Node.js | v26.2.0 (linux-arm64) |
| dsh (`@deepseek-ai/dsh`) | 0.2.1-rc.2 |
| pnpm | 12.16.1 |

---

## 1. Package Contents

| File | Size | Purpose |
| --- | --- | --- |
| `deepseek-harness-user-offline.tar.gz` | ~302 MB | Self-contained runtime (expands to ~1.1 GB): Node.js + dsh + pnpm + desktop icon |
| `install-on-target.sh` | 5 KB | Installer to run on the **target machine** (no sudo) |
| `make-offline.sh` | 8 KB | Rebuilds the offline package on an **internet-connected build machine** |
| `node-v26.2.0-linux-arm64.tar.xz` | 31 MB | Official Node.js prebuilt binary; only needed when rebuilding, not on the target |
| `icon.jpeg` | 5 KB | Desktop launcher icon |
| `README.md` / `README_EN.md` | — | Chinese / English documentation |

> The target machine only needs **`deepseek-harness-user-offline.tar.gz` + `install-on-target.sh`**; the remaining files can stay on the build machine.

---

## 2. Requirements

- OS: Kylin V10 (`aarch64`), glibc ≥ 2.28 (V10 ships 2.31, which is sufficient).
- Disk space: about 1.5 GB for the install directory (302 MB archive + 1.1 GB extracted).
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

When you see `✓ 安装完成。` ("installation complete"), it worked. The process usually takes 1–3 minutes, mostly spent extracting.

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
| Append `~/.local/bin` to `PATH` if missing | `~/.profile` |
| Initialize the web profile and add required offline pnpm settings | `~/.dsh/profiles/web/pnpm-workspace.yaml` |
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
└── dsh-web-icon.jpeg         # desktop icon source

~/.local/bin/dsh-web          # launcher
~/.dsh/                       # user data and config (kept outside the package; survives upgrades)
```

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
4. `icon.jpeg` in the same directory as the script.

### Build

```bash
# Change the architecture if needed: arm64 / x64
sed -i 's/^ARCH=.*/ARCH="x64"/' make-offline.sh

bash make-offline.sh
```

The script deploys Node.js → installs `@deepseek-ai/dsh` and `pnpm` globally → smoke-tests the web service → regenerates `install-on-target.sh` → produces `deepseek-harness-user-offline.tar.gz`.

> ⚠️ **Caution**: the build script installs dsh into the **current user's** `~/.local/opt/deepseek-harness` and, after the smoke test, runs `rm -rf "$HOME/.dsh"` to remove test data. Run it on a clean build machine (or a dedicated container); if the machine already has dsh data, back up `~/.dsh` first.

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
- The package contains official Node.js prebuilt binaries and public npm packages. Verify integrity with `sha256sum` before and after copying.
- The installer never runs `sudo` and never writes to system directories; every change can be reverted with the commands in section 6.
