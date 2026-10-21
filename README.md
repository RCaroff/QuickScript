<p align="center">
  <img src="icon/readme-icon.png" alt="QuickScript icon" width="83">
</p>

<h1 align="center">QuickScript</h1>

A tiny macOS menu bar app to register your scripts (bash, Python, Ruby, Node, …) and **run them in one click**: silently in the background, in a Terminal window, or straight from the Finder's context menu.

- Native Swift + AppKit, no dependencies, no Xcode project
- Typed parameters: text fields, checkboxes and drop-down lists generated from a comment header
- Automatic detection of interactive `stdin` prompts
- Per-run log files and a live logs window with history
- Finder Services to run a script on the selected files or in the current folder
- Built-in **MCP server** so an AI assistant (e.g. Claude) can create, edit and run your scripts

## Requirements

- macOS 11 (Big Sur) or later
- Xcode Command Line Tools (`xcode-select --install`), needed to compile

## Installation

```bash
git clone https://github.com/RCaroff/QuickScript.git
cd QuickScript
./build.sh --install
```

| Command | Effect |
|---------|--------|
| `./build.sh` | Builds `build/QuickScript.app` |
| `./build.sh --run` | Builds, then launches the app |
| `./build.sh --install` | Builds, copies the app to `~/Applications` **and** `/Applications` (asks for your password via `sudo`), refreshes the Services menu and restarts Dock/Finder |

The app is ad-hoc signed for local use. It has no Dock icon: look for <picture><source media="(prefers-color-scheme: dark)" srcset="icon/menu-icon-white@3x.png"><img src="icon/menu-icon@3x.png" alt="QuickScript menu bar icon" height="18" align="top"></picture> in the menu bar.

## Usage

### The menu

While scripts are running, the menu bar icon shows how many are running, e.g. `(2)`.

Each registered script has a submenu:

| Item | Action |
|------|--------|
| **Run** | Runs the script silently (hold **⌥ Option** to show **Run in terminal**) |
| **Stop** | Replaces *Run* while the script is running. Kills the script and all its child processes |
| **Reveal in Finder** | Shows the script file |
| **Show / Hide logs window** | Live output and history of past runs |
| **Edit parameters…** | Graphical editor for the `@param` header (see below) |
| **Rename… / Delete** | Rename the entry or remove it from the list (the file itself is kept) |

The bottom of the menu has:

- **Add a script…**: register existing script files.
- **Create new bash script…**: create an empty script and register it.
- **Open config.json** (hold **⌥** for **Show config.json**).
- **Refresh**: reload the configuration after editing it by hand.
- **Always run in terminal** and **Always show logs window at run**: global preferences.
- **Enable MCP server** and **Configure MCP port…**: see [MCP server](#mcp-server).

If a script file was moved or deleted, clicking it lets you pick its new location or remove the entry.

### Silent mode (default)

- The script runs in the background. stdout and stderr are captured.
- If it exits with **code 0**, nothing is shown.
- If it exits with a **non-zero code**, an alert shows the output with a **Copy logs** button.
- If it waits for input on `stdin` (`read` in bash, `input()` in Python…), a native dialog asks for the value and sends it to the script (see [Interactive prompts](#interactive-prompts)).

### Terminal mode

**Run in terminal** (or the *Always run in terminal* preference) opens the script in iTerm if it's installed, otherwise in Terminal.app. The session is still recorded to the log file. The **Stop** button isn't available in this mode, since the process lives outside QuickScript.

## Script parameters: `# @param`

Declare parameters in comment lines at the top of the script, after the shebang and before the first line of code. When you click **Run**, QuickScript shows a dialog with one control per parameter and passes the values to the script as arguments.

```bash
#!/usr/bin/env bash
# @param filename=note.txt               File name
# @param content                         File content (may be empty)
# @param -env:enum(dev|staging|prod)=dev Target environment
# @param -dry_run:bool=true              Simulate without changing anything
```

### Syntax

```
# @param NAME[:TYPE][=DEFAULT] [free description until end of line]
```

| Part | Meaning |
|------|---------|
| `NAME` | Parameter name, shown as the label |
| `:TYPE` | Optional. Control shown in the dialog (see below) |
| `=DEFAULT` | Optional. Pre-filled value |
| description | Optional. Shown next to the label |

`// @param` is accepted too (handy for JavaScript).

### Types

| Type | Control | Value passed to the script |
|------|---------|----------------------------|
| `string` (default) | Text field | The text entered |
| `bool` | Checkbox | `true` or `false` |
| `enum(a\|b\|c)` | Drop-down list | The selected option |

- A `bool` default must be `true` or `false`. Without a default, the box is unchecked.
- An `enum` default must be one of the options. Otherwise the first option is selected.
- Enum values can't contain spaces or `|`.

### Positional or flag arguments

- **Positional** (default): values are passed in declaration order, as `$1`, `$2`, …
- **Flag**: if the name starts with `-` (e.g. `-env`), QuickScript passes `-env value`. An empty value means the flag isn't passed at all. A `bool` always has a value, so its flag is always passed.

A flag-style script usually parses its arguments like this:

```bash
while [[ $# -gt 0 ]]; do
  case "$1" in
    -env)     ENV="$2"; shift 2 ;;
    -dry_run) DRY_RUN="$2"; shift 2 ;;
    *) echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
done
```

### Parameter editor

**Edit parameters…** opens a table where you can add, remove, edit and reorder (drag and drop) parameters, including their type (empty or `string`, `bool`, `enum(a|b|c)`). Saving rewrites the `# @param` lines in the script file. The rest of the file is left untouched.

## Interactive prompts

In silent mode, scripts run in a pseudo-terminal, so `read -p`, `input()` and similar calls behave as they would in a terminal. QuickScript shows an input dialog when the output:

- ends without a newline, has been idle for about 350 ms, and its last character is `:`, `?`, `>` or `]` (e.g. `Name: `), or
- has been idle for more than 2.5 s without a newline.

Good to know:

- `PYTHONUNBUFFERED=1` is set so that Python prints its prompt before blocking.
- This detection is a heuristic. A script that prints a progress line without `\n` and then works for a while can trigger a false prompt. Click **Cancel script**, or end such lines with `\n`. When you can, prefer `@param` over runtime prompts.

## Finder integration (Services)

QuickScript adds two entries to the Finder's **Services** menu. Both show a picker to choose which script to run.

| Service | Where to right-click | What the script receives |
|---------|----------------------|--------------------------|
| **Run with QuickScript…** | On one or more selected files | `QS_CONTEXT_FILE_PATH`: the selected paths, one per line |
| **Run with QuickScript here…** | On an empty area of a Finder window or the Desktop | `QS_CONTEXT_TARGET_PATH`: the folder being shown |

Command-line arguments stay reserved for the `@param` values. Context is passed through environment variables only.

```bash
# Iterate over selected files
while IFS= read -r f; do
  echo "Processing $f"
done <<< "$QS_CONTEXT_FILE_PATH"

# Work in the current Finder folder
target="${QS_CONTEXT_TARGET_PATH:-$HOME/Desktop}"
touch "$target/new-file.txt"
```

The *here* service asks the Finder for its current folder through AppleScript. macOS asks for Automation permission the first time. You can change it later in *System Settings → Privacy & Security → Automation*.

**The Services don't show up?** macOS refreshes the Services menu lazily, and recent versions hide third-party services by default.

1. Run `./build.sh --install`. If that's not enough: `/System/Library/CoreServices/pbs -update && killall Finder`.
2. Enable them in *System Settings → Keyboard → Keyboard Shortcuts → Services → Files and Folders*.

## Environment variables

| Variable | When | Content |
|----------|------|---------|
| `QS_CONTEXT_FILE_PATH` | *Run with QuickScript…* | Selected file paths, one per line |
| `QS_CONTEXT_TARGET_PATH` | *Run with QuickScript here…* | Folder shown in the Finder |
| `PYTHONUNBUFFERED=1` | Silent mode | Python prompts are printed immediately |
| `TERM=dumb` | Silent mode | Discourages ANSI color codes |

⚠️ Scripts launched from the app start with `$PWD` set to `/`. Never use `$PWD` as an implicit target folder. Use `QS_CONTEXT_TARGET_PATH` or an explicit `@param` instead.

## Supported interpreters

| Extension | Interpreter |
|-----------|-------------|
| `.sh`, `.bash` | `bash` |
| `.zsh` | `zsh` |
| `.py` | `python3` |
| `.rb` | `ruby` |
| `.js`, `.mjs` | `node` |
| `.pl` | `perl` |
| `.php` | `php` |
| other (executable bit + shebang) | executed directly |

Interpreters are resolved through `/usr/bin/env`, using the `PATH` the app inherits. That `PATH` is usually more limited than your shell's, so use absolute paths for tools installed in unusual locations.

## Logs

Every run writes a new log file:

```
~/Library/Application Support/QuickScript/logs/<script name>/<script name>-YYYY-MM-DD_HHMMSS.log
```

It contains a header (script, arguments, context), the full output, and the exit code. The **logs window** shows the output of the current run live, and its history menu lets you reopen past runs.

## Configuration

Everything (the script list and the preferences) lives in one JSON file:

```
~/Library/Application Support/QuickScript/config.json
```

```json
{
  "preferences": {
    "alwaysRunInTerminal": false,
    "alwaysShowLogsAtRun": false,
    "mcpServerEnabled": false,
    "mcpServerPort": 8765
  },
  "scripts": [
    { "id": "UUID", "name": "My script", "path": "/absolute/path/script.sh" }
  ]
}
```

You can edit it by hand. Click **Refresh** in the menu afterwards. Parameters aren't stored here: they're read from each script's `# @param` header.

## MCP server

QuickScript includes a [Model Context Protocol](https://modelcontextprotocol.io) server so an AI assistant can manage and run your scripts.

| Tool | Description |
|------|-------------|
| `list_scripts` | Lists scripts with their parameters (name, type, options, default, description) |
| `add_script` | Creates a new script from its content and parameter list |
| `update_params` | Replaces a script's `@param` header |
| `run_script` | Runs a script with parameter values, without any dialog |
| `delete_script` | Removes a script from the list (optionally deletes the file) |

A parameter is described as `{ "name", "type": "string" | "bool" | "enum", "options": [...], "default", "description" }`.

⚠️ `run_script` runs code on your machine. Only connect assistants you trust, and review what they ask to run.

Two transports are available:

- **stdio** (recommended): the client starts `QuickScript --mcp-stdio` in headless mode, with no UI. `run_script` waits for the script to finish and returns `exitCode`, `stdout` and `stderr`. Terminal mode isn't available.
- **Local HTTP** (Streamable HTTP on `127.0.0.1` only): turn it on with **Enable MCP server** in the menu. The default port is `8765`; change it with **Configure MCP port…**.

### Connect Claude Desktop (stdio)

1. Install the app with `./build.sh --install`, so the binary is at `/Applications/QuickScript.app/Contents/MacOS/QuickScript`.
2. In Claude Desktop, open **Settings → Developer → Edit Config**. Add a `mcpServers` key at the root of the file and keep the existing content:

   ```json
   {
     "mcpServers": {
       "quickscript": {
         "command": "/Applications/QuickScript.app/Contents/MacOS/QuickScript",
         "args": ["--mcp-stdio"]
       }
     }
   }
   ```

3. **Quit Claude Desktop completely (⌘Q)** and relaunch it. The config is only read at startup.
4. The tools show up under **Developer** and in the tools menu of the message box. Local stdio servers don't appear on the *Connectors* page.

The headless server and the menu bar app share `config.json`. After an assistant adds a script, click **Refresh** in the menu to see it.

### Troubleshooting

- **Check that the server responds.** This should print a JSON line containing `"serverInfo"`:

  ```bash
  echo '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}' \
    | /Applications/QuickScript.app/Contents/MacOS/QuickScript --mcp-stdio
  ```

- **Validate the Claude config.** A stray comma silently breaks loading:

  ```bash
  python3 -m json.tool < "$HOME/Library/Application Support/Claude/claude_desktop_config.json"
  ```

- **Client logs**: `~/Library/Logs/Claude/mcp.log`
- **Changes not taken into account after a rebuild**: run `./build.sh --install` again, then fully quit and relaunch both QuickScript and the MCP client.

## Example scripts

The `test-scripts/` folder contains small demos. Add them with **Add a script…**.

| Script | Demonstrates |
|--------|--------------|
| `new-file.sh` | `@param` text fields (folder, name, content) |
| `interactive-prompt.sh` | Runtime `stdin` prompts |
| `error-demo.sh` | Error alert (exit code 1 with stdout/stderr) |
| `silent-ok.sh` | Fully silent successful run |
| `files-info.sh` | *Run with QuickScript…* on a file selection |
| `flatten-folder.sh` | *Run with QuickScript here…*: moves all files from subfolders into the current folder |
| `crop-images.sh`, `resize-images.sh` | Image processing (`sips`) on the Finder selection or a path parameter |
| `hello.*` | One script per supported interpreter |

## Contributing

The code layout is described in [`architecture.md`](architecture.md). Development notes, conventions and known pitfalls are in [`CLAUDE.md`](CLAUDE.md). Issues and pull requests are welcome.

## Roadmap ideas

- Global keyboard shortcuts per script
- Reordering scripts in the menu by drag and drop
- Remembering the last values entered for each script
- Search / filter when the menu gets long
- *Clear* button in the logs window, *Retry* button in the error alert

## License

QuickScript is released under the [MIT License](LICENSE).
