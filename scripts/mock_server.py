#!/usr/bin/env python3
"""Local DeepSeek-compatible mock used for end-to-end UI verification."""
import json
import sys
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse

LOG = open("/tmp/ds-focus-mock.log", "a", buffering=1)


def log(message):
    stamp = time.strftime("%H:%M:%S")
    LOG.write(f"[{stamp}] {message}\n")


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.0"

    def log_message(self, fmt, *args):
        log("http " + fmt % args)

    def _json(self, obj, status=200):
        body = json.dumps(obj, ensure_ascii=False).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        path = urlparse(self.path).path
        log(f"GET {path} auth={self.headers.get('Authorization', '')[:20]}")
        if path == "/models":
            self._json({
                "object": "list",
                "data": [
                    {
                        "id": "deepseek-flash",
                        "object": "model",
                        "owned_by": "deepseek",
                        "name": "DeepSeek-V4.1-Flash",
                        "context_window": 1048576,
                        "max_output_tokens": 393216,
                        "input_modalities": ["text", "image"],
                        "output_modalities": ["text"],
                        "effort": {"supported_levels": ["low", "high", "max"], "default_level": "high"}
                    },
                    {
                        "id": "deepseek-v4-pro",
                        "object": "model",
                        "owned_by": "deepseek",
                        "name": "DeepSeek-V4-Pro",
                        "context_window": 1048576,
                        "max_output_tokens": 393216,
                        "input_modalities": ["text"],
                        "output_modalities": ["text"],
                        "effort": {"supported_levels": ["low", "high", "max"], "default_level": "high"}
                    }
                ]
            })
        else:
            self._json({"error": {"message": "not found", "type": "invalid_request_error"}}, 404)

    def do_POST(self):
        path = urlparse(self.path).path
        length = int(self.headers.get("Content-Length") or 0)
        raw = self.rfile.read(length)
        try:
            body = json.loads(raw or b"{}")
        except Exception:
            body = {}
        log(f"POST {path} body={json.dumps(body, ensure_ascii=False)[:900]}")

        if path == "/v1/tools/search":
            query = body.get("query", "")
            results = [
                {
                    "rerank_score": 2.8,
                    "title": "DeepSeek 发布新一代模型：原生搜索与百万上下文",
                    "url": "https://api-docs.deepseek.com/updates",
                    "snippet": "DeepSeek 更新了模型与工具 API。",
                    "summary": "DeepSeek 最新一代模型支持长上下文、思考强度控制，并提供 Search 与 Fetch API，方便 Agent 获取实时网页信息。",
                    "content": "",
                    "site_name": "DeepSeek API Docs",
                    "site_icon": None,
                    "date": "2026-10-17T10:00:00+00:00",
                    "authority": 4
                },
                {
                    "rerank_score": 2.3,
                    "title": "Agent 开发工具正在走向统一",
                    "url": "https://example.com/agent-tools",
                    "snippet": "工具调用和长上下文成为标配。",
                    "summary": "多家厂商的开发者工具开始围绕工具调用、长期记忆和可观测性构建统一的 Agent 工作流。",
                    "content": "",
                    "site_name": "Example Tech",
                    "site_icon": None,
                    "date": "2026-10-17T08:30:00+00:00",
                    "authority": 3
                },
                {
                    "rerank_score": 1.9,
                    "title": "桌面 AI 搜索的下一站",
                    "url": "https://example.com/desktop-ai",
                    "snippet": "从启动器到对话框，桌面入口正在变化。",
                    "summary": "新一代桌面工具尝试把搜索、问答和操作系统快捷入口结合，让用户不必切换应用即可完成任务。",
                    "content": "",
                    "site_name": "Example Design",
                    "site_icon": None,
                    "date": "2026-10-16T12:00:00+00:00",
                    "authority": 2
                }
            ]
            self._json({"results": results})
            return

        if path not in ("/chat/completions", "/v1/chat/completions"):
            self._json({"error": {"message": "not found", "type": "invalid_request_error"}}, 404)
            return

        messages = body.get("messages", [])
        last = messages[-1] if messages else {}
        last_role = last.get("role")
        tools = body.get("tools") or []
        last_user = ""
        for message in reversed(messages):
            if message.get("role") == "user":
                last_user = message.get("content") or ""
                break
        has_tool_result = any(message.get("role") == "tool" for message in messages)
        log(f"last_role={last_role} tools={len(tools)} tool_result={has_tool_result} q={last_user[:80]}")

        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream; charset=utf-8")
        self.send_header("Cache-Control", "no-cache")
        self.send_header("Connection", "close")
        self.end_headers()

        def send(delta, finish=None, usage=None):
            obj = {
                "id": "chatcmpl-mock",
                "object": "chat.completion.chunk",
                "created": int(time.time()),
                "model": body.get("model", "deepseek-flash"),
                "choices": [{"index": 0, "delta": delta, "finish_reason": finish}],
            }
            if usage is not None:
                obj["usage"] = usage
            self.wfile.write(("data: " + json.dumps(obj, ensure_ascii=False) + "\n\n").encode())
            self.wfile.flush()
            time.sleep(0.055)

        def done(usage_override=None):
            usage = usage_override or {
                "prompt_tokens": 320,
                "completion_tokens": 240,
                "total_tokens": 560,
                "prompt_tokens_details": {"cached_tokens": 0},
                "completion_tokens_details": {"reasoning_tokens": 42},
            }
            obj = {
                "id": "chatcmpl-mock",
                "object": "chat.completion.chunk",
                "created": int(time.time()),
                "model": body.get("model", "deepseek-flash"),
                "choices": [{"index": 0, "delta": {}, "finish_reason": "stop"}],
                "usage": usage,
            }
            self.wfile.write(("data: " + json.dumps(obj, ensure_ascii=False) + "\n\n").encode())
            self.wfile.write(b"data: [DONE]\n\n")
            self.wfile.flush()

        # Tool call path: no successful tool result yet and tools were offered.
        if last_role == "user" and tools and not has_tool_result and ("科技" in last_user or "新闻" in last_user or "搜索" in last_user):
            send({"role": "assistant", "content": "", "reasoning_content": "用户想看今天的科技动态，需要先检索最新信息。我会用 DeepSeek 搜索 API 查询今天的重要新闻。"})
            send({"role": "assistant", "content": "", "reasoning_content": "先搜索中文科技新闻，再挑选出可信度较高的来源。"})
            send({
                "role": "assistant",
                "content": "",
                "tool_calls": [{
                    "index": 0,
                    "id": "call_mock_search_1",
                    "type": "function",
                    "function": {"name": "web_search", "arguments": ""},
                }],
            })
            time.sleep(0.1)
            send({
                "role": "assistant",
                "content": "",
                "tool_calls": [{
                    "index": 0,
                    "function": {"arguments": "{\"query\": \"今日科技新闻 AI 2026-10-17\"}"},
                }],
            })
            usage = {
                "prompt_tokens": 120,
                "completion_tokens": 45,
                "total_tokens": 165,
                "completion_tokens_details": {"reasoning_tokens": 38},
            }
            obj = {
                "id": "chatcmpl-mock",
                "object": "chat.completion.chunk",
                "created": int(time.time()),
                "model": body.get("model", "deepseek-flash"),
                "choices": [{"index": 0, "delta": {}, "finish_reason": "tool_calls"}],
                "usage": usage,
            }
            self.wfile.write(("data: " + json.dumps(obj, ensure_ascii=False) + "\n\n").encode())
            self.wfile.write(b"data: [DONE]\n\n")
            self.wfile.flush()
            return

        # Full synthesized answer only immediately after the tool result.
        if has_tool_result and last_role == "tool":
            send({"role": "assistant", "reasoning_content": "搜索结果已经返回。我来提炼三条有价值的动态，并用链接标注来源。"})
            send({"role": "assistant", "content": "今天值得关注的科技动态主要集中在三个方向：\n\n"})
            send({"role": "assistant", "content": "1. **模型与搜索能力继续融合**：DeepSeek 新模型已支持原生联网搜索和最高 100 万 token 上下文，"})
            send({"role": "assistant", "content": "开发者可以在一次对话里完成检索、阅读和总结 [DeepSeek API Docs](https://api-docs.deepseek.com/updates)。\n"})
            send({"role": "assistant", "content": "2. **Agent 工具链趋于统一**：围绕工具调用、长期记忆和可观测性的工作流正在成为开发者工具的标配 [Example Tech](https://example.com/agent-tools)。\n"})
            send({"role": "assistant", "content": "3. **桌面 AI 入口升温**：搜索框开始变成可以直接完成任务的对话入口，而不只是跳转链接 [Example Design](https://example.com/desktop-ai)。\n\n"})
            send({"role": "assistant", "content": "如果你想深入其中一条，我可以继续展开。"})
            done()
            return

        if any(token in last_user for token in ["详细", "展开", "第二条", "第二"]):
            send({"role": "assistant", "reasoning_content": "用户希望延续上一轮，进一步展开 Agent 工具链这一条。"})
            send({"role": "assistant", "content": "第二条说的是 **Agent 工具链的统一**。它包含三层：\n\n"})
            send({"role": "assistant", "content": "- **协议层**：工具调用、MCP 等接口逐渐标准化。\n"})
            send({"role": "assistant", "content": "- **上下文层**：长上下文让一次任务可以携带更多历史与中间结果。\n"})
            send({"role": "assistant", "content": "- **可观测层**：开发者需要看到每次搜索、工具调用和 token 消耗。\n\n"})
            send({"role": "assistant", "content": "这也是为什么桌面 AI 搜索入口开始和完整的 Agent 工作流结合。"})
            done()
            return

        send({"role": "assistant", "reasoning_content": "用户问了一个简单问题，直接给出简短回答即可。"})
        send({"role": "assistant", "content": "你好，我是 DeepSeek 聚焦。你可以在任意应用里用快捷键唤起我，然后直接提问。"})
        done()


def main():
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8765
    server = ThreadingHTTPServer(("127.0.0.1", port), Handler)
    log(f"mock server listening on http://127.0.0.1:{port}")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
        LOG.close()


if __name__ == "__main__":
    main()
