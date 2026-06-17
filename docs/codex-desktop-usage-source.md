# Codex 桌面端用量数据源

CodexPlus 第一版真实数据源读取 Codex 桌面端本地日志，不访问网络。

## 文件位置

候选位置：

1. `~/.codex/logs_2.sqlite`
2. `~/.codex/sqlite/logs_2.sqlite`

Provider 会以只读方式打开可读候选库，并选择最新可解析快照；这样即使 Codex 桌面端在不同版本间迁移日志位置，也不会因为较旧数据库仍然可读而显示过期额度。文件监听会跟随最近有写入活动的数据库、WAL、SHM 文件：

- `logs_2.sqlite`
- `logs_2.sqlite-wal`
- `logs_2.sqlite-shm`

文件监听用于近实时刷新：文件变化后先等待 5 秒防抖，再进入自动刷新队列；自动刷新最快 20 秒执行一次。启动时会立即刷新一次，之后每 30 分钟轮询一次作为兜底。

## 表结构

当前使用 `logs` 表：

```text
ts
target
feedback_log_body
```

只解析满足以下条件的日志：

```text
target = codex_api::endpoint::responses_websocket
feedback_log_body contains "usage" or "codex.rate_limits"
```

解析阶段还会继续要求 websocket event 的 JSON 类型是以下之一：

```json
{"type": "response.completed"}
{"type": "codex.rate_limits"}
```

这样可以避开请求体、工具调用参数、普通日志正文和包含查询命令的伪命中。

## 用量字段

从 `response.usage` 读取：

```json
{
  "input_tokens": 1200,
  "input_tokens_details": {
    "cached_tokens": 400
  },
  "output_tokens": 300,
  "output_tokens_details": {
    "reasoning_tokens": 80
  },
  "total_tokens": 1500
}
```

字段映射：

- `input_tokens` -> `UsageSnapshot.inputTokens`
- `input_tokens_details.cached_tokens` -> `UsageSnapshot.cachedInputTokens`
- `output_tokens` -> `UsageSnapshot.outputTokens`
- `output_tokens_details.reasoning_tokens` -> `UsageSnapshot.reasoningTokens`
- `total_tokens` -> `UsageSnapshot.totalTokens`

注意：cached input 是 input tokens 的子集，reasoning tokens 是 output tokens 的子集，所以 `totalTokens` 使用日志里的 `total_tokens`，不再把所有字段相加，避免重复计算。

## 剩余额度字段

从 `codex.rate_limits` 事件读取 Codex 桌面端本地记录的额度状态：

```json
{
  "type": "codex.rate_limits",
  "plan_type": "prolite",
  "rate_limits": {
    "allowed": true,
    "limit_reached": false,
    "primary": {
      "used_percent": 41,
      "window_minutes": 300,
      "reset_after_seconds": 2335,
      "reset_at": 1781631830
    },
    "secondary": {
      "used_percent": 56,
      "window_minutes": 10080,
      "reset_after_seconds": 118153,
      "reset_at": 1781747648
    }
  },
  "credits": null,
  "promo": null
}
```

字段映射：

- `plan_type` -> `UsageRateLimitSnapshot.planType`
- `rate_limits.allowed` -> `UsageRateLimitSnapshot.allowed`
- `rate_limits.limit_reached` -> `UsageRateLimitSnapshot.limitReached`
- `primary.window_minutes == 300` -> 5 小时额度窗口
- `secondary.window_minutes == 10080` -> 每周额度窗口
- `used_percent` -> 已用百分比，App 显示 `100 - used_percent` 作为剩余百分比
- `reset_at` -> 对应窗口的刷新时间

当前本机会员账号样本中，`credits` 和 `promo` 为 `null`，没有出现免费账号月度金额字段。代码只对月度窗口做保守预留，不猜测不存在的金额字段。

## 聚合方式

- 当前会话：取最新 `response.completed` 所在 thread，并汇总该 thread 最近可解析 turn 的用量。
- 今日总量：汇总本地自然日内所有可解析 `response.completed` 的 `total_tokens`。
- 更新时间：使用最新可解析 usage 或 rate limit 记录的 `ts`。

当前实现会读取每个候选库最近 2000 条候选日志，再在内存里解析和去重，并选择 `updatedAt` 最新的有效快照。

## 错误处理

- 找不到数据库：返回 provider unavailable。
- 数据库无法打开：返回 SQLite 错误。
- 找不到可解析 usage：返回 provider unavailable。
- 格式异常：忽略单条异常日志，继续解析其它候选记录。
- 日志轮转或文件变化：文件监听触发刷新，5 秒防抖后进入自动刷新队列。
- 数据源静默不写入：30 分钟轮询作为兜底。
