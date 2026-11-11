# rea-team

这是一个可以直接拿来用的目录模板：把 Claude Code 拆成四个子代理，用两间房做净室逆向。分析侧可以调用 [REA](https://rea.tools)，重建侧只看一份行为规格。目标必须是你拥有、或者已经得到授权可以检查的软件。

方法来自 [@Gyome1_](https://x.com/Gyome1_) 的文章《How to Turn Claude Code Into a Reverse Engineering Team with 7 Steps》（<https://x.com/Gyome1_/status/2111774069783720195>）。四个代理文件和 `run-team.sh` 的流程按原文实现。本仓库补上了墙的检查脚本、规格交接、以及 Claude Code 参考 devcontainer 那套出站白名单。

REA 本身是 `rea-agents` 这个 npm 包。防火墙脚本改编自 Claude Code 参考开发容器（<https://github.com/anthropics/claude-code/tree/main/.devcontainer>，说明见 <https://code.claude.com/docs/en/devcontainer>）。

## 四个角色

| 角色 | 房间 | 做什么 |
| --- | --- | --- |
| Analyst | `lab/`（宿主机，可以用 REA） | 只查一个功能，把证据写进 `analysis/evidence.md` |
| Spec Writer | `lab/` | 把证据写成只描述行为的 `handoff/SPEC.md` |
| Rebuilder | `clean/`（容器 `rea-clean`，没有 REA） | 只根据 `SPEC.md` 实现，并为每条测试用例写测试 |
| Verifier | `lab/` | 用同一批输入跑原程序和重建结果，写 `report.md` |

一次只处理一句话能说清的功能。Analyst 不写规格，也不写实现。Spec Writer 不把未知写成需求。Rebuilder 不回答 Open questions。Verifier 不改规格，也不改重建结果。

## 两间房

`lab/` 和 `clean/` 是两间房，中间只有一扇窄门。

- `lab/` 放目标程序、证据和规格。REA 只装在这一侧。Analyst、Spec Writer、Verifier 都在这里跑。
- `clean/` 挂进名为 `rea-clean` 的容器，容器内路径是 `/work`。这间房没有 `rea` 命令，也看不见 `lab/`、`target/`。
- 唯一穿过墙的文件是 `handoff/SPEC.md`。先做泄漏检查，再复制到 `clean/SPEC.md` 并去掉写权限。
- 把 MCP 服务器从界面里藏起来不算隔离。同一台机器上的代理只要有 shell，仍然可以 `npx rea-agents`，也可以直接读磁盘上的证据。真正的隔离是单独的容器、单独的文件系统，再加上出站白名单。

镜像定义在仓库根目录的 `.devcontainer/`，不在挂进容器的 `clean/` 里面。Rebuilder 改不了下一次构建用的防火墙脚本。容器启动时如果看见 `/lab`、`/target` 或 `/work/lab`，会直接拒绝启动。

## 环境要求

在 **lab 这一侧**（Windows 上就是 WSL 里的 Ubuntu）准备：

- Node.js **22.19+**、**24.11+** 或 **26+**。`node -v` 先确认。
- Docker，并且允许容器使用 `NET_ADMIN` 和 `NET_RAW`（出站防火墙要用）。
- Claude Code CLI（`claude`）。
- 可选：Ghidra 和 JDK。只有原生程序和游戏才需要。

`scripts/fill-analyst-tools.sh` 用 Node 读 `doctor.json`。没有 Node 时改用 `jq`。两种实现接受同一类结构；对不上已知结构时脚本会停下来，并写出手动填法，不会编造工具名。

## Windows 11

在 Windows 11 上，整套流程跑在 **WSL2 的 Ubuntu** 里，不要跑在 PowerShell、CMD 或 Git Bash 里。

1. 安装 WSL2 和 Ubuntu。管理员 PowerShell：

   ```powershell
   wsl --install -d Ubuntu
   ```

   装完后从开始菜单打开 Ubuntu，建好 Linux 用户。

2. 安装 Docker Desktop。在 Settings → Resources → WSL integration 里打开 Ubuntu 的集成。打开 Ubuntu 终端，`docker version` 能看到 Server 即表示集成生效。

3. 在 **Ubuntu 里面** 安装 Node（22.19+、24.11+ 或 26+）和 Claude Code CLI，例如用 nvm。不要用 Windows 自己的 `node.exe`，也不要在 PowerShell 里装 Claude Code 再指望 WSL 能找到它。

   ```bash
   node -v
   npm install -g @anthropic-ai/claude-code
   claude
   ```

   `claude` 的登录也在 WSL 里做一次。

4. 把仓库克隆到 **WSL 的 Linux 文件系统**，例如 `~/src/rea-team`。不要放在 `/mnt/c/...`。跨到 Windows 盘符后，Docker 绑定挂载会变慢，权限和文件监视也容易坏。

   ```bash
   mkdir -p ~/src
   cd ~/src
   git clone <你的仓库地址> rea-team
   cd rea-team
   ```

5. 后面的每条命令都在这个 Ubuntu 终端里执行。Ghidra 如果要装，也解压到 WSL 文件系统里，`GHIDRA_INSTALL_DIR` 和 `JAVA_HOME` 用 Linux 路径（`/home/...`），不要用 `C:\...`。

Docker Desktop 需要把足够的内存分给 WSL。防火墙初始化时容器要访问 GitHub 和 Anthropic 的 API，用来解析白名单地址。

## 安装 REA（只装在 lab 这一侧）

在 WSL 的仓库目录外、或者仓库的 `lab/` 里都可以，只要 **不要** 在 `rea-clean` 容器里装：

```bash
node -v
npx rea-agents@latest setup
npm install --global rea-agents
npx -y rea-agents@latest doctor --client claude_code --skill --json
rea update
```

`setup` 会把 MCP 服务器 `rea` 写进 `~/.claude.json`，并放一个 skill 到 `~/.claude/skills`。确认计划后再批准。工具到了 Claude Code 里的名字是 `mcp__rea__*`。

原生程序和游戏再加：

```bash
export GHIDRA_INSTALL_DIR=/absolute/path/to/ghidra
export JAVA_HOME=/absolute/path/to/jdk
npx -y rea-agents@latest doctor --provider ghidra --json
```

把这两行写进 `~/.bashrc`，下次打开 Ubuntu 仍然有效。

## 启动净室，然后从白名单去掉 npm

容器名是 `rea-clean`。它只把 `./clean` 挂到 `/work`，另外有一个命名卷保存容器里的 Claude 登录（`/home/node/.claude`），不挂宿主机家目录，也不挂 Docker 套接字。

第一次构建时 `ALLOW_NPM` 默认为 `1`，白名单里包含 `registry.npmjs.org`，方便在容器里安装重建项目自己的依赖。依赖装完之后必须把它拿掉，否则 Rebuilder 可以 `npx rea-agents`，把分析工具重新拉进净室。

```bash
docker compose up -d --build
```

如果这次重建需要 npm 依赖，趁注册表还开着，在容器里装好：

```bash
docker exec -it -u node rea-clean bash
cd /work
npm install
exit
```

然后在宿主机重建，把注册表移出白名单：

```bash
ALLOW_NPM=0 docker compose up -d --build --force-recreate
```

这一步会用 `--build-arg ALLOW_NPM=0` 把标志写进镜像里的 `/etc/rea-clean/allow-npm`（root 所有，权限 444）。防火墙脚本只读这个文件。容器里的 `node` 用户没有权限改它，`sudo` 也只能运行 `/usr/local/bin/init-firewall.sh`。

确认注册表已经不可达（这条命令应当失败）：

```bash
docker exec rea-clean curl -I --connect-timeout 5 https://registry.npmjs.org
```

再跑墙检查。三条命令全部失败，并且容器内的 `ALLOW_NPM` 标志为 `0`，脚本才算通过：

```bash
scripts/check-wall.sh
```

通过时会看到类似：

```text
ok: which rea failed inside rea-clean
ok: npx --no-install rea-agents --version failed inside rea-clean
ok: ls /lab /target failed inside rea-clean
```

`ALLOW_NPM` 仍是 `1`、标志文件缺失或读取失败时，脚本会以非零状态退出。给 Rebuilder 开工之前，必须用 `ALLOW_NPM=0` 重建容器并通过检查。

容器里的 Claude 需要自己的登录，不要把宿主机的 `~/.claude` 挂进去：

```bash
docker exec -it -u node rea-clean claude
```

登录保存在卷 `rea-clean-claude` 里。容器起不来时看 `docker logs rea-clean`。常见原因是构建白名单时连不上 GitHub 或 `api.anthropic.com`，或者挂载把 `lab/` 带进了容器（入口脚本会拒绝这种挂载）。

日常启动用 `docker compose`。`.devcontainer/devcontainer.json` 指向同一份 compose，并把工作区挂载限制为仓库里的 `clean/`。用 Dev Containers 打开的是仓库根目录。如果编辑器报告挂载点冲突，就只用 `docker compose`，不要改成把整个仓库挂进容器。

## 第一次运行

下面假设你已经在 WSL 的仓库根目录，容器 `rea-clean` 在跑，而且 npm 注册表已经从白名单拿掉。

1. 选一个你拥有的 Electron 应用或 .NET 程序，放进 `lab/target/`。Electron 可以是解开的应用目录或 `app.asar`；.NET 可以是你有权检查的程序集。一次只写一句话功能，例如「搜索如何给结果排序」。不要把整个应用当成一个任务。

2. 导出工具目录，并写进 Analyst 的 `tools` 行：

   ```bash
   cd lab
   rea doctor --json > analysis/doctor.json
   cd ..
   scripts/fill-analyst-tools.sh
   ```

   `analysis/doctor.json` 已被 `.gitignore` 排除。不同版本的 `rea doctor --json` 结构不一样：有的给出带 `name` 和 `surface` 的工具条目，有的只有 `tool_availability` 分组，有的只有 `identity.catalog.counts.mcp_tools` 这种计数。脚本认得前两类，以及名为 `tools` / `mcp_tools` / `tool_names` 的数组。

   文件能解析、但里面没有工具名时，脚本以状态码 2 退出，并打印手动填法。手动填的时候：

   ```bash
   jq -r '.. | objects | .name? // empty' lab/analysis/doctor.json
   ```

   然后在 lab 这一侧打开 Claude Code，抄下真实的 `mcp__rea__*` 名字，改 `lab/.claude/agents/analyst.md` 正面信息里的 `tools` 行。保留 `Read, Grep, Glob, Write`，不要给 Analyst 加 `Bash`。不要自己编工具名。

   只看会写成什么样、先不改文件：`scripts/fill-analyst-tools.sh --dry-run`。

3. 跑这一句话功能。`run-team.sh` 会先 `cd lab`，所以目标路径按 `lab/` 来写：

   ```bash
   ./run-team.sh target/YourApp "how search ranks results"
   ```

   脚本先运行 Analyst → Spec Writer，再最多重建、验证三轮。每轮先通过墙检查，再用 `scripts/handoff.sh` 检查非空规格和泄漏、复制规格并设为只读，然后运行容器里的 Rebuilder → Verifier。验证前删除旧报告；本轮必须生成非空的 `report.md`，且最后一行严格符合 `RESULT wrong=<n> crash=<n>`。最后一行是 `RESULT wrong=0 crash=0` 时结束。三轮之后仍有 `wrong` 或 `crash`，脚本以状态码 2 退出，留下 `lab/report.md` 给你看。

Verifier 会执行原始程序。放进 `lab/target/` 的程序应当是你愿意在这台机器上运行的；拿不准时，先在虚拟机或沙箱里跑 Verifier 那一侧。

### 不用 run-team.sh 时，手动走一遍

在 `lab/` 里打开 Claude Code：

```text
Use the analyst agent on target/YourApp. Feature: how search ranks results.
Use the spec-writer agent to write handoff/SPEC.md from analysis/evidence.md.
```

回到仓库根目录：

```bash
scripts/leak-check.sh
scripts/handoff.sh
docker exec -u node rea-clean claude -p "Use the rebuilder agent on /work/SPEC.md"
```

重建结果在 `clean/src/`。Verifier 在 lab 里比较 `target/` 和 `rebuild/`。`run-team.sh` 会把容器里的 `/work/src` 拷到 `lab/rebuild/`。手动跑时自己拷一次：

```bash
rm -rf lab/rebuild
docker cp rea-clean:/work/src lab/rebuild
```

然后再让 Verifier 写 `lab/report.md`。

## 怎么读这三份结果

按这个顺序读，不要跳。

1. `lab/analysis/evidence.md`  
   每条结论都带标签。`observation` 是直接看到的，旁边有地址或调用点。`inference` 写它靠哪些观察。`unknown` 是这个功能需要、但还没证明的点。地址只应该出现在这里。

2. `lab/handoff/SPEC.md` 的 **Open questions**  
   证据里每一个 `unknown` 都变成这里的一条。未知不能写成 Architecture、Public API 或 Test Cases 里的需求。规格里只有行为：公开接口、数据模型、用户看得到的功能、读写的文件格式、错误处理。一个没见过原二进制的人，应当能只靠这份文档做出兼容实现。  
   `scripts/leak-check.sh` 用的就是这条 grep：

   ```bash
   grep -nEi '0x[0-9a-f]{5,}|sub_[0-9a-f]+|var_[0-9a-f]+|FUN_[0-9a-f]+' lab/handoff/SPEC.md
   ```

   有输出就是规格泄漏了反编译名字或地址，不能送过墙。

3. `lab/report.md`  
   三组输入各自的匹配率：普通使用、边界值（空、最大长度、Unicode）、畸形或损坏输入。每一条差异写明输入、原程序输出、重建输出，并标成 `compatible`（规格允许）、`wrong` 或 `crash`。文件最后一行是：

   ```text
   RESULT wrong=<n> crash=<n>
   ```

   `wrong` 和 `crash` 都是 0，才算这一轮对齐。`compatible` 可以留下。Verifier 否决之后，下一轮只是让 Spec Writer 把 `wrong` 和 `crash` 补进 Test Cases，而不是手改 `clean/src`。

## 五个代价高的错误

- 在同一个操作系统账户里同时跑 REA 和 Rebuilder
- 因为规格「看起来很干净」就跳过泄漏 grep
- 把 `evidence.md` 交给 Rebuilder 当上下文
- Verifier 否决之后手工改重建结果
- 让 Analyst 面对整个应用，而不是一个功能

`lab/CLAUDE.md` 把授权、三种标签和这五条写成了 lab 侧的房屋规则。第一条规定：目标必须是你拥有或已获授权检查的软件。

## 法律说明

这个模板只用于合法的研究、互操作、软件保存，以及你拥有或被授权检查的软件。许可证可以禁止逆向工程，即使当地法律允许互操作或备份。授权说不清就停，不要靠猜测开工。

这里没有破解、绕过授权或攻击别人系统的步骤。Analyst 的工作是为一个你有权检查的功能收集行为证据。

## 目录

```text
.devcontainer/          # 净室镜像、出站防火墙、devcontainer.json
docker-compose.yml      # 容器名 rea-clean，只挂载 ./clean → /work
run-team.sh             # 一轮功能：分析 → 规格 → 重建 → 核对，最多三轮
scripts/
  check-wall.sh         # 三条墙检查都失败才通过
  leak-check.sh         # 规格泄漏 grep
  handoff.sh            # 把 SPEC 复制到 clean/ 并设为只读
  fill-analyst-tools.sh # 用 doctor.json 填 Analyst 的 tools 行
lab/
  CLAUDE.md
  .claude/agents/       # analyst、spec-writer、verifier
  target/               # 你的程序（不提交）
  analysis/             # 证据、doctor.json（不提交）
  handoff/              # SPEC.md（不提交）
clean/
  .claude/agents/rebuilder.md
  src/                  # 重建结果（不提交）
```

`.gitignore` 排除 `lab/target/` 的内容、`lab/analysis/` 的产出、`handoff/SPEC.md`、`rebuild/`、`report.md`，以及常见二进制后缀。证据和目标程序不要提交。

## 脚本自检

`scripts/fill-analyst-tools.sh --self-test` 用几份假的 doctor 结构检查 Node 和 jq 是否抽出同一组名字，并确认只改正面信息里的 `tools` 行。
