"""Unit tests that need no database or network."""
from verlium.extract import from_text, youtube_id
from verlium.ingest import chunk_text, page_at
from verlium.migrate import statements
from verlium.modeltests import vision_test_image
from verlium.rag import Chunk, finalize_citations, strip_citations, text_query
from pathlib import Path


def test_chunks_cover_text_with_overlap():
    text = ("Sentence number %d is here. " * 400) % tuple(range(400))
    spans = chunk_text(text, 1200, 200)
    assert spans[0][0] == 0 and spans[-1][1] == len(text)
    for (a1, b1), (a2, b2) in zip(spans, spans[1:]):
        assert a2 < b1, "consecutive chunks overlap"
        assert a2 > a1, "progress"
        assert b1 - a1 <= 1200
    assert all(text[a:b].strip() for a, b in spans)


def test_chunk_short_text():
    assert chunk_text("hello", 1200, 200) == [(0, 5)]


def test_page_at():
    pages = [(0, 1), (100, 2), (250, 3)]
    assert page_at(pages, 0) == 1 and page_at(pages, 150) == 2 and page_at(pages, 999) == 3
    assert page_at([], 5) is None


def test_citations_renumbered_in_order():
    chunks = [Chunk(f"c{i}", "s", "Doc", f"text {i}", i * 10, i * 10 + 9, None, i) for i in range(5)]
    text, cites = finalize_citations("A [4]. B [2, 4]. C [9] D [1]", chunks)
    assert text == "A [1]. B [2][1]. C  D [3]"
    assert [c["chunk_id"] for c in cites] == ["c3", "c1", "c0"]
    assert [c["n"] for c in cites] == [1, 2, 3]


def test_strip_citations():
    assert strip_citations("Fact [1][2] and more [3, 4].") == "Fact and more."


def test_text_query_sanitises():
    assert text_query("What is the role of chlorophyll's {magnesium}?") == "{role} ACCUM {chlorophyll} ACCUM {magnesium}"
    assert text_query("a an ?") is None


def test_youtube_ids():
    assert youtube_id("https://www.youtube.com/watch?v=dQw4w9WgXcQ&t=1") == "dQw4w9WgXcQ"
    assert youtube_id("https://youtu.be/dQw4w9WgXcQ") == "dQw4w9WgXcQ"
    assert youtube_id("https://example.com") is None


def test_text_decoding():
    assert from_text("héllo".encode("utf-8")).text == "héllo"
    assert from_text("﻿bom".encode("utf-8")).text == "bom"


def test_schema_splits():
    sql = (Path(__file__).parents[1] / "verlium" / "schema.sql").read_text(encoding="utf-8")
    stmts = statements(sql)
    assert len(stmts) > 15
    assert all(not s.rstrip().endswith("/") for s in stmts)
    assert any(s.startswith("CREATE OR REPLACE TRIGGER") and s.rstrip().endswith("END;") for s in stmts)


def test_vision_image_png():
    assert vision_test_image()[:8] == b"\x89PNG\r\n\x1a\n"


def test_think_splitter_across_chunks():
    from verlium.providers import ThinkSplitter
    sp = ThinkSplitter()
    parts = []
    for chunk in ["Hel", "lo <thi", "nk>pondering", " more</th", "ink> answer"]:
        parts += sp.feed(chunk)
    parts += sp.flush()
    think = "".join(t for k, t in parts if k == "thinking")
    text = "".join(t for k, t in parts if k == "text")
    assert think == "pondering more"
    assert text == "Hello  answer"


def test_parse_json_tolerant():
    from verlium.providers import parse_json
    assert parse_json('```json\n{"a": 1}\n```') == {"a": 1}
    assert parse_json('Sure! Here it is: {"cards": [1, 2]} hope that helps') == {"cards": [1, 2]}


def _fake_provider(handler):
    """OpenAICompat whose HTTP layer is an in-process httpx.MockTransport."""
    import httpx
    from verlium.providers import OpenAICompat, Provider
    c = OpenAICompat(Provider("p", "mock", "http://mock/v1", "openai", "k", {}))
    c._client = lambda *a, **k: httpx.AsyncClient(transport=httpx.MockTransport(handler))
    return c


def test_embed_falls_back_on_400():
    import asyncio, json
    import httpx
    seen = []

    def handler(req):
        body = json.loads(req.content)
        seen.append((len(body["input"]), "dimensions" in body))
        if "dimensions" in body or len(body["input"]) > 2:
            return httpx.Response(400, json={"error": {"message": "JSON body validation failed"}})
        return httpx.Response(200, json={"data": [{"index": i, "embedding": [float(len(t))]}
                                                  for i, t in enumerate(body["input"])]})

    out = asyncio.run(_fake_provider(handler).embed("m", ["a", "bb\x00", "ccc", "dddd", "e"], 256))
    assert out == [[1.0], [2.0], [3.0], [4.0], [1.0]]  # order kept, NUL stripped
    assert seen[0] == (5, True) and seen[1] == (5, False)


def test_chat_json_drops_unsupported_params():
    import asyncio, json
    import httpx

    def handler(req):
        body = json.loads(req.content)
        if "response_format" in body or "temperature" in body:
            return httpx.Response(400, json={"error": "JSON body validation failed"})
        return httpx.Response(200, json={"choices": [{"message": {"content": '{"ok": 1}'}}]})

    assert asyncio.run(_fake_provider(handler).chat_json("m", "hi", temperature=0.2)) == {"ok": 1}


def test_activity_report_tracks_job():
    from verlium import activity
    tok = activity.current_job.set({"id": "j1", "kind": "ingest"})
    try:
        before = activity.last_seq()
        activity.report("step", progress=40)
        ev = activity.since(before)
        assert ev[-1]["job_id"] == "j1" and ev[-1]["progress"] == 40
    finally:
        activity.current_job.reset(tok)


def test_citations_skip_code_and_math():
    from verlium.rag import Chunk, finalize_citations
    c = Chunk(id="c", source_id="s", source_title="T", text="t", char_start=0, char_end=1, page=None, seq=0)
    text = 'See [1]. $[0,1]$ ok.\n```chart\n{"data": [1,2,3]}\n```'
    out, cites = finalize_citations(text, [c])
    assert '{"data": [1,2,3]}' in out and "$[0,1]$" in out and len(cites) == 1


def test_embed_retries_transient_errors():
    import asyncio
    import httpx
    calls = []

    def handler(req):
        calls.append(1)
        if len(calls) == 1:
            return httpx.Response(503, json={"error": "busy"})
        return httpx.Response(200, json={"data": [{"index": 0, "embedding": [1.0]}]})

    assert asyncio.run(_fake_provider(handler).embed("m", ["a"])) == [[1.0]] and len(calls) == 2


def test_plain_converts_decimals():
    import json
    from decimal import Decimal
    from verlium.db import plain
    v = plain({"temperature": Decimal("0.7"), "max_tokens": Decimal("4096"), "x": [Decimal("1.5")]})
    assert v == {"temperature": 0.7, "max_tokens": 4096, "x": [1.5]} and isinstance(v["max_tokens"], int)
    json.dumps(v)


def test_attachment_classify_and_image_processing():
    import io
    from PIL import Image
    from verlium.attachments import _process_image, classify
    assert classify("a.PNG", None) == ("image", "image/png")
    assert classify("clip.mov", "application/octet-stream") == ("video", "video/quicktime")
    assert classify("doc.pdf", "application/pdf") is None
    buf = io.BytesIO()
    Image.new("RGBA", (4000, 1000), (255, 0, 0, 128)).save(buf, "PNG")
    info = _process_image(buf.getvalue())
    model = Image.open(io.BytesIO(info["model"]))
    assert (info["width"], info["height"]) == (4000, 1000) and max(model.size) == 1568 and model.mode == "RGB"


def test_build_messages_with_images():
    from verlium.rag import build_messages
    msgs = build_messages(None, None, [], "What is this?", [], images=["data:image/jpeg;base64,AA"],
                          attachment_text="ATTACHED VISUALS")
    content = msgs[-1]["content"]
    assert content[0]["type"] == "text" and "ATTACHED VISUALS" in content[0]["text"]
    assert content[1]["image_url"]["url"].startswith("data:image/jpeg")
