[English](README.md) | **简体中文**

<p align="center"><img src="assets/logo.svg" alt="agent.sh" width="200"></p>

# agent.sh

*没有工具的智能体：模型写 bash，bash 回话。*

**模型的回复不会被解析成工具调用——它直接交给一个长期存活的 shell 执行，而那个 shell 打印出来的内容就是下一条消息。** 模型的输出*就是* shell 的输入；文件、作业、管道和状态 shell 本来就有，所以这套 harness 唯一要解决的问题是边界：一个块在哪里结束、它的输出是什么，尤其当输出由后台进程迟到写入、当负载本身是不可信的字节时。

[![licence: AGPL-3.0](https://img.shields.io/badge/licence-AGPL--3.0-blue.svg)](LICENSE)

## 快速开始

两条命令，没有构建步骤，没有依赖文件——只需 bash 5.1+、coreutils、`iconv`、`jq`，走真实 API 时再加 `curl`：

```sh
git clone https://github.com/ZisIsNotZis/agent.sh
cd agent.sh

bash test/run.sh                                # 全部不变量，不调 API，约半分钟
bash agent.sh --blocks examples/tour.sh         # 模型的位置由文件顶替的 harness
```

之后读 `.session/<时间戳>-<pid>/traj.md`：那就是整段对话，一轮一轮，形状和模型当时读到的一模一样。

要让真模型来驱动——默认是 `reasoning_effort: low` 的 `deepseek-flash`，每轮约 800 个 prompt token，所以一次只要不到一分钱：

```sh
export DEEPSEEK_API_KEY=…                       # deepseek.com；用的是 completions API，不需要别的 key
bash agent.sh --task 'report the three largest files in this repo, with sizes' --max-turns 6
```

## 现在能做什么

- **一轮一个块，跑在一个保留状态的 shell 里。** `cd`、变量、文件、正在运行的进程、shell 历史都跨块存活；只有块自己起的进程随块结束。
- **一个块无法用内建命令伪造的边界。** 块被写进它自己的文件，然后追加一行：`>"$slipdir/<nonce>.$?"`——没有命令词的纯重定向，于是 shell 自己的解析器在块跑完后，把退出状态写进一个*文件名*。输出则按字节数从块自己的文件里读回。
- **语法不成立的块根本不会到达 shell**，直接报成 `[status 2]` 的语法错误。
- **截断，并指名原始文件。** 长输出截到最后 `--lines N` 行（默认 100），表头写出块自己的原始文件路径，模型用 `sed -n` 翻——完整输出既不复制也不再发送。
- **二进制输出被拒绝**，而不是编码：`[binary output, N bytes, not shown]`。
- **后台任务。** `bgrun [-n note] cmd…` 起一个作业后立刻返回；作业结束会自己开启一轮，以带备注的 `Job:` 消息送达，绝不会插进一个仍在读取的块里。
- **每轮一行计量**——`<|meter|>`，含 `prompt`、`hit`、`miss`、`out` 和累计值——追加进轨迹，同时打到 stderr。
- **压缩是一条追加的消息**，所以 prompt 前缀永不改变：`--compact-at N` 在某一轮 prompt 达到 `N` token 后压缩一次。
- **续跑只做追加**（`--resume`）；`--stub FILE` 用一个脚本替换 API，做免费、可复现的运行——`test/run.sh` 用的就是它。

## 一轮长什么样

来自 hands 的每条消息都以 `Bash:` 开头、以 `[status N]` 结尾，每个块的正文和它的回复并排记在轨迹里。

```
Bash: job 1 started, pid 2484919, log /…/jobs/1/log
[status 0]
Bash: the model keeps writing blocks while the job runs
[status 0]
Bash: job 1 exited 0
[status 0]
Bash: [truncated: total 150 lines, showing last 100; full output at /…/raw/6.raw]
line 51
…
[status 0]
```

## 为什么是这个形状

所有 agent 框架回答"模型怎么行动"的方式，都是去它的文本里解析一个工具调用。这个项目把这个问句删掉了。

这条边界是一个文件，不是一条流。重定向无法被块定义的函数遮蔽、替换或拦截，所以这份状态报告是整个协议里唯一一样块无法用内建命令伪造的东西。

剩下的只有那条明写的"无沙箱"边界，别无其他：块可以读自己的源码，因此能找到 nonce 并自己写一个 slip 文件。这一点连复现一起写在 [`docs/design.md`](docs/design.md) D11 里，而不是声称它不存在——同时写下的还有一件廉价但可见的事：遮蔽了 `.` 的块会破坏*下一个*块的传输，表现为超时，而不是静默的成功。

## 架构

两个进程，一个方向的控制。harness 是外层 bash——它拥有 API 调用、轨迹、标签和截断——它的 hands 是一个没有 tty 的 `setsid bash`，经由 `coproc` 访问。hands 拿到 `BASH_ENV`，通过它只拿到两个函数；其余一切都是它本来就是的那个 shell：`cd`、环境变量、`&`、`wait -n -p`、文件。

| 函数 | 作用 |
|---|---|
| `bgrun [-n note] cmd…` | 在后台启动 `cmd`，把作业状态写到 `$AGENT_SH_JOBS/<seq>/`（`cmd`、`pid`、`note`、`log`），立刻返回 |
| `bgwait` | 用 `wait -n -p` 回收一个已完成的作业，记下退出状态，打印 `job <seq> exited <status>`；没有作业在跑时打印 `no jobs pending` 并返回 `127` |

```
agent.sh                    harness，单个 bash 文件：API 调用、轨迹、标签、截断、drain
prompt/system.md            系统提示：模型没有工具列表可学，协议只能写在这里
test/run.sh                 不变量检查，免费、确定性，配一个桩模型
test/check-prefix.sh        从轨迹重建每个请求，要求逐字节相同地拿回来
test/stub-model.sh          给免费运行用的脚本化模型
examples/tour.sh            用 --blocks 走一遍"一轮长什么样"
probes/                     设计所依赖的五项测量，一分钟内可全部重跑
runs/2026-10-26-demo/       一次无人值守运行，按当时的样子提交
docs/design.md              定下来的设计，以及每条落选的分支和淘汰它的测量
docs/roadmap.md             里程碑、它的四个条件、包状态表、每个决定及其代价
docs/brief-m1.md            定下这个里程碑的方向
```

作业结束会开启新的一轮，而不是拼进仍在读取的块里，所以轨迹永远按顺序可读，代价是一次额外的往返。

## 如何开发

这里没有构建、没有包管理器、也没有测试框架：`test/run.sh` 就是普通 bash，必须保持能在 bash 5.1+、coreutils、`iconv` 和 `jq` 下运行。

```sh
bash test/run.sh                             # 全部不变量；退出码 0 代表成立
bash agent.sh --blocks examples/tour.sh       # 一次免费运行，结果读 .session/…/traj.md
bash agent.sh --stub test/stub-model.sh --task 'x'   # 用脚本化模型跑整个循环
for p in probes/*.sh; do bash "$p"; done      # 重新测量设计的依据，约一分钟
```

最重要的那条不变量是 `test/check-prefix.sh`：每次运行，它只凭轨迹重建每一个请求，要求逐字节等于实际发出的请求；然后读运行自己的 `usage` 行，一旦 prompt 缓存不再命中就失败。于是"前缀永不改变"是对记录做的算术，而不是一句承诺。真实路径就是它背后薄薄一层 `curl`。

有两个 probe 是故意失败的——`02-single-shell.sh`，以及 `03-boundary-nonce.sh` 的最后一行——因为它们正是落选分支的证据。

## 参与贡献

见 [`CONTRIBUTING.md`](CONTRIBUTING.md)。简短版：每个发现的 bug 都要变成 `test/run.sh` 里的一条不变量；设计的改动要带着决定它的测量写进 `docs/design.md`。

## 路线图

**已实现**——只有一个里程碑 `M1`，它的包 `P1`–`P8` 全部落地：边界（`test/run.sh`）、hands 的环境与 `bgrun`/`bgwait`、带续跑和计量的一轮、系统提示、前缀稳定的 `/compact`、演示运行、独立评审，以及块无法遮蔽的上报通道。`bash test/run.sh` 不花任何计量费用就检查上面列出的全部不变量；`runs/2026-10-26-demo/` 保存着它们为之而建的那份轨迹——二十轮、一条 `Job:`、两次截断、一次压缩、83,724 个 prompt token，并且 `bash runs/2026-10-26-demo/check-prefix.sh` 能从记录重建全部 20 个请求，0 失败。

**计划中**——这个里程碑的验收，是一个人读完轨迹和 harness，这件事这个仓库没法替自己做。在那之后，刻意不做的东西也已经是决定：没有工具调用协议（那正是这个项目），没有沙箱，没有 tmux，没有 pty，没有 Python，v0 没有流式输出，块运行期间没有实时输出。

它瞄准的未来是：一个原语——后台的一个进程——承载子智能体、定时器与提醒，而 harness 小到一个读者能亲手找出里面的 bug。这次运行到底好不好，是唯一留给读者的判断。

## 演示运行

[`runs/2026-10-26-demo/`](runs/2026-10-26-demo/) 是一次无人值守运行，按当时的样子提交：轨迹、计量、请求、智能体留下的工作区，以及重新生成这一切的命令。`notes.md` 指出每条证据落在哪一行，也说明了这次运行付出了什么代价。

## 不适合谁

不适合想要沙箱化、多用户或联网的 agent 服务的人，不适合想要 Python 或 TUI harness 的人，也不适合想要工具调用协议的人。这里没有任何东西被沙箱化，这是刻意的：harness 位于模型能触及的一切之外，而模型的手就是 shell 状态本身。

一个块被限制在 300 秒（`AGENT_SH_BLOCK_TIMEOUT`），因为一个读 stdin 的块否则会让无人值守的运行永远挂住；代价是它建立起来的 shell 状态，报告消息里会写明这一点。等待后台作业同样有上限（`AGENT_SH_JOB_WAIT`，600 秒）：超过上限的作业会被报告为仍在运行，留给之后某一轮，而不是结束整个运行。

## 许可证

AGPL-3.0-only，见 [`LICENSE`](LICENSE)。

Copyright (C) 2026 ZisIsNotZis.
