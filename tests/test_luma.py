"""Exercise Luma's install/stream lifecycle without downloads or an installed model."""
import hashlib
import importlib.util
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import tarfile
import tempfile
import threading
import time
import unittest
from unittest.mock import patch

SOURCE = Path(__file__).resolve().parents[1] / "config/quickshell/MacShell/bin/luma.py"
spec = importlib.util.spec_from_file_location("macshell_luma", SOURCE)
luma = importlib.util.module_from_spec(spec)
spec.loader.exec_module(luma)


class Response(io.BytesIO):
    def __init__(self, content, status=200, headers=None):
        super().__init__(content)
        self.status = status
        self.headers = headers or {}


class DownloadTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.path = Path(self.temp.name) / "model.gguf"
        self.payload = b"GGUF-model-fixture"
        self.digest = hashlib.sha256(self.payload).hexdigest()
        self.cancel = threading.Event()

    def download(self):
        luma.download("https://example.invalid/model", self.path, len(self.payload), self.digest, self.cancel, lambda *_: None)

    def test_download_is_verified_before_publishing(self):
        with patch.object(luma.urllib.request, "urlopen", return_value=Response(self.payload)):
            self.download()
        self.assertEqual(self.path.read_bytes(), self.payload)
        self.assertFalse(self.path.with_suffix(".gguf.part").exists())

    def test_corrupt_download_never_replaces_installed_model(self):
        self.path.write_bytes(b"old model")
        with patch.object(luma.urllib.request, "urlopen", return_value=Response(b"X" * len(self.payload))):
            with self.assertRaisesRegex(RuntimeError, "verification"):
                self.download()
        self.assertEqual(self.path.read_bytes(), b"old model")

    def test_download_resumes_partial_file(self):
        self.path.with_suffix(".gguf.part").write_bytes(self.payload[:5])
        with patch.object(luma.urllib.request, "urlopen", return_value=Response(self.payload[5:], 206, {"Content-Range": "bytes 5-17/18"})) as opening:
            self.download()
        self.assertEqual(opening.call_args.args[0].get_header("Range"), "bytes=5-")
        self.assertEqual(self.path.read_bytes(), self.payload)

    def test_server_ignoring_range_restarts_download(self):
        self.path.with_suffix(".gguf.part").write_bytes(self.payload[:5])
        with patch.object(luma.urllib.request, "urlopen", return_value=Response(self.payload)):
            self.download()
        self.assertEqual(self.path.read_bytes(), self.payload)

    def test_cancel_preserves_partial_without_publishing(self):
        self.path.with_suffix(".gguf.part").write_bytes(self.payload[:5])
        self.cancel.set()
        with patch.object(luma.urllib.request, "urlopen", return_value=Response(self.payload[5:], 206, {"Content-Range": "bytes 5-17/18"})):
            with self.assertRaises(luma.Cancelled):
                self.download()
        self.assertFalse(self.path.exists())
        self.assertTrue(self.path.with_suffix(".gguf.part").exists())

    def test_wrong_resume_range_is_rejected(self):
        self.path.with_suffix(".gguf.part").write_bytes(self.payload[:5])
        with patch.object(luma.urllib.request, "urlopen", return_value=Response(self.payload, 206, {"Content-Range": "bytes 0-17/18"})):
            with self.assertRaisesRegex(RuntimeError, "resume range"):
                self.download()
        self.assertFalse(self.path.exists())

    def test_truncated_download_can_be_resumed(self):
        with patch.object(luma.urllib.request, "urlopen", return_value=Response(self.payload[:5])):
            with self.assertRaisesRegex(RuntimeError, "incomplete"):
                self.download()
        self.assertEqual(self.path.with_suffix(".gguf.part").read_bytes(), self.payload[:5])

    def test_archive_cannot_write_outside_runtime_directory(self):
        archive = Path(self.temp.name) / "runtime.tar"
        with tarfile.open(archive, "w") as stream:
            member = tarfile.TarInfo("../escape")
            member.size = 1
            stream.addfile(member, io.BytesIO(b"x"))
        with self.assertRaises(tarfile.FilterError):
            luma.extract_runtime(archive, Path(self.temp.name) / "runtime")
        self.assertFalse((Path(self.temp.name) / "escape").exists())


class LumaTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.events = []
        self.app = luma.Luma(self.events.append, self.base / "data", self.base / "config/luma.json")
        self.addCleanup(self.app.close)
        self.runtime = patch.object(self.app, "runtime", return_value="/fixture/llama-server")
        self.runtime.start()
        self.addCleanup(self.runtime.stop)

    def install_fixture(self, model=luma.DEFAULT_MODEL):
        payload = b"GGUF-fixture"
        meta = luma.MODELS[model]
        original = dict(meta)
        meta.update(bytes=len(payload), sha256=hashlib.sha256(payload).hexdigest())
        self.addCleanup(lambda: (meta.clear(), meta.update(original)))
        path = self.app.model_path(model)
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(payload)
        self.app.record_model(model, "fixture")

    def test_opening_status_does_not_download_or_create_model_directory(self):
        with patch.object(luma, "remote_json", side_effect=AssertionError("network access")):
            self.app.handle({"action": "status"})
        self.assertFalse(self.app.data.exists())
        self.assertFalse(self.events[0]["ready"])

    def test_chat_requires_install(self):
        with self.assertRaisesRegex(RuntimeError, "Install"):
            self.app.chat("Halo")
        self.assertEqual(self.app.history, [])

    def test_model_selection_is_persisted_without_loading(self):
        self.install_fixture("gemma-3-4b")
        self.app.handle({"action": "select", "model": "gemma-3-4b"})
        self.assertEqual(json.loads(self.app.config.read_text())["model"], "gemma-3-4b")
        self.assertIsNone(self.app.server)
        with self.assertRaisesRegex(RuntimeError, "Install or import"):
            self.app.handle({"action": "select", "model": "gemma-3-1b"})

    def test_model_ids_cannot_escape_data_directory(self):
        for action in ("remove", "install", "select", "import"):
            with self.assertRaises(ValueError):
                self.app.handle({"action": action, "model": "../../outside"})

    def test_history_is_local_and_conversations_can_be_deleted(self):
        self.app.append("user", "Ringkas teks ini")
        self.app.append("assistant", "Ringkasan")
        first = self.app.current
        self.app.handle({"action": "new"})
        self.app.append("user", "Percakapan kedua")
        self.app.handle({"action": "conversation", "id": first})
        self.app.handle({"action": "delete", "id": first})
        persisted = json.loads((self.app.data / "conversations.json").read_text())
        self.assertEqual(len(persisted), 1)
        self.assertNotEqual(persisted[0]["id"], first)
        self.app.handle({"action": "clear_history"})
        self.assertEqual(json.loads((self.app.data / "conversations.json").read_text()), [])

    def test_cannot_switch_or_delete_during_generation(self):
        self.app.busy = "chat"
        for action in ("new", "clear_history", "remove", "select"):
            with self.assertRaisesRegex(RuntimeError, "Wait"):
                self.app.handle({"action": action, "model": luma.DEFAULT_MODEL})
        self.app.busy = ""

    def test_stream_stays_on_loopback_and_stores_complete_answer(self):
        self.install_fixture()
        content = b'data: {"choices":[{"delta":{"content":"Halo "}}]}\n\ndata: {"choices":[{"delta":{"content":"dunia"}}]}\n\ndata: [DONE]\n'
        with patch.object(self.app, "ensure_server"), patch.object(luma.LOCAL_HTTP, "open", return_value=Response(content)) as opening:
            self.app.chat("Halo")
        request = opening.call_args.args[0]
        self.assertTrue(request.full_url.startswith("http://127.0.0.1:"))
        payload = json.loads(request.data)
        self.assertNotIn("chat_template_kwargs", payload)
        self.assertNotIn("/no_think", payload["messages"][0]["content"])
        self.assertEqual(self.app.history[0]["messages"][-1]["content"], "Halo dunia")
        self.assertTrue(any(e["event"] == "token" for e in self.events))

    def test_idle_releases_owned_runtime(self):
        class Server:
            terminated = False
            def terminate(self): self.terminated = True
            def wait(self, timeout=None): return 0
            def poll(self): return None
        server = Server()
        self.app.server = server
        self.app.last_used = time.monotonic() - 91
        self.app.idle()
        self.assertTrue(server.terminated)
        self.assertIsNone(self.app.server)

    def test_install_error_returns_ui_to_idle_with_retry_available(self):
        def fail():
            raise RuntimeError("Offline")
        self.app.job_start("install", fail)
        self.app.job.join(timeout=2)
        self.assertEqual(self.app.busy, "")
        self.assertTrue(any(e.get("message") == "Offline" for e in self.events))
        self.assertEqual(self.events[-1]["event"], "done")

    def test_remove_cleans_partial_and_leaves_other_models(self):
        self.install_fixture()
        self.install_fixture("gemma-3-4b")
        self.app.model_path(luma.DEFAULT_MODEL).with_suffix(".gguf.part").write_bytes(b"partial")
        self.app.handle({"action": "remove", "model": luma.DEFAULT_MODEL})
        self.assertFalse(self.app.model_path(luma.DEFAULT_MODEL).exists())
        self.assertFalse(self.app.model_path(luma.DEFAULT_MODEL).with_suffix(".gguf.part").exists())
        self.assertTrue(self.app.model_path("gemma-3-4b").exists())
        self.assertFalse(self.app.model_record(luma.DEFAULT_MODEL))

    def test_metadata_selects_official_quantized_file_and_pins_revision(self):
        model = luma.MODELS["gemma-3-1b"]
        metadata = {"sha": "revision", "siblings": [{"rfilename": model["file"],
                    "lfs": {"sha256": model["sha256"], "size": model["bytes"]}}]}
        with patch.object(luma, "remote_json", return_value=metadata):
            result = luma.model_metadata(model)
        self.assertIn("/resolve/revision/", result["url"])
        self.assertTrue(result["url"].endswith(model["file"]))
        self.assertEqual(result["digest"], model["sha256"])
        self.assertEqual(result["size"], model["bytes"])

    def test_metadata_without_checksum_is_rejected(self):
        model = luma.MODELS["gemma-3-1b"]
        with patch.object(luma, "remote_json", return_value={"siblings": [{"rfilename": model["file"]}]}):
            with self.assertRaisesRegex(RuntimeError, "checksum"):
                luma.model_metadata(model)

    def test_metadata_cannot_replace_the_pinned_gemma_file(self):
        model = luma.MODELS["gemma-3-1b"]
        metadata = {"sha": "revision", "siblings": [{"rfilename": model["file"],
                    "lfs": {"sha256": "a" * 64, "size": model["bytes"]}}]}
        with patch.object(luma, "remote_json", return_value=metadata):
            with self.assertRaisesRegex(RuntimeError, "pinned"):
                luma.model_metadata(model)

    def test_import_rejects_a_wrong_file_without_publishing(self):
        source = self.base / "wrong.gguf"
        source.write_bytes(b"not the official model")
        self.app.handle({"action": "import", "model": luma.DEFAULT_MODEL, "path": str(source)})
        self.app.job.join(timeout=2)
        self.assertTrue(any("not the official" in event.get("message", "") for event in self.events))
        self.assertFalse(self.app.model_path(luma.DEFAULT_MODEL).exists())
        self.assertFalse(self.app.model_record(luma.DEFAULT_MODEL))

    def test_verified_import_records_provenance_and_activates(self):
        payload = b"GGUF-import-fixture"
        model = luma.MODELS[luma.DEFAULT_MODEL]
        original = dict(model)
        model.update(bytes=len(payload), sha256=hashlib.sha256(payload).hexdigest())
        self.addCleanup(lambda: (model.clear(), model.update(original)))
        source = self.base / "official.gguf"
        source.write_bytes(payload)
        self.app.handle({"action": "import", "model": luma.DEFAULT_MODEL, "path": str(source)})
        self.app.job.join(timeout=2)
        self.assertEqual(self.app.model_path(luma.DEFAULT_MODEL).read_bytes(), payload)
        record = self.app.model_record(luma.DEFAULT_MODEL)
        self.assertEqual(record["method"], "import")
        self.assertEqual(record["sha256"], model["sha256"])
        self.assertEqual(json.loads(self.app.config.read_text())["model"], luma.DEFAULT_MODEL)

    def test_runtime_selects_cpu_binary_with_publisher_checksum(self):
        assets = [{"name": "llama-b9999-bin-ubuntu-x64.tar.gz", "digest": "sha256:" + "b" * 64, "size": 999, "browser_download_url": "https://github.com/ggml-org/llama.cpp/releases/download/b9999/runtime.tar.gz"},
                  {"name": "llama-b9999-bin-ubuntu-cuda-x64.tar.gz"}]
        with patch.object(luma.platform, "machine", return_value="x86_64"), patch.object(luma, "remote_json", return_value=[{"assets": assets}]):
            result = luma.runtime_asset()
        self.assertEqual(result["digest"], "b" * 64)

    def test_actual_bridge_starts_and_exits_without_loading_or_installing(self):
        result = subprocess.run([sys.executable, "-B", str(SOURCE)],
                                input='{"action":"status"}\n', text=True, capture_output=True, timeout=5,
                                env=dict(os.environ, XDG_RUNTIME_DIR=str(self.base),
                                         XDG_CONFIG_HOME=str(self.base / "config"),
                                         XDG_DATA_HOME=str(self.base / "state")))
        self.assertEqual(result.returncode, 0, result.stderr)
        events = [json.loads(line) for line in result.stdout.splitlines()]
        self.assertEqual([event["event"] for event in events], ["hello", "status", "history", "messages"])
        self.assertFalse(events[1]["loaded"])
        self.assertFalse(events[1]["ready"])
        self.assertFalse((self.base / "state").exists())



class PersonalContextTests(unittest.TestCase):
    def test_only_enabled_local_sources_enter_the_prompt(self):
        import sqlite3
        with tempfile.TemporaryDirectory() as directory:
            base=Path(directory)
            app=luma.Luma(lambda event:None,base/'luma',base/'luma.json')
            try:
                database=base/'context/context.db';database.parent.mkdir()
                with sqlite3.connect(database) as conn:
                    conn.executescript('CREATE TABLE sources(kind TEXT,enabled INTEGER); CREATE TABLE items(id INTEGER,kind TEXT,title TEXT,body TEXT,provenance TEXT); CREATE VIRTUAL TABLE fts USING fts5(title,body);')
                    conn.execute('INSERT INTO sources VALUES(?,?)',('mail',0))
                    conn.execute('INSERT INTO items VALUES(?,?,?,?,?)',(1,'mail','Orchid meeting','Orchid meets on Monday. '+('extra '*200),json.dumps({'kind':'mail','ref':'message-1'})))
                    conn.execute('INSERT INTO fts(rowid,title,body) VALUES(?,?,?)',(1,'Orchid meeting','Orchid meets on Monday'))
                self.assertEqual(app.personal_context('When is the Orchid meeting?'),'')
                with sqlite3.connect(database) as conn:conn.execute('UPDATE sources SET enabled=1')
                result=app.personal_context('When is the Orchid meeting?')
                self.assertIn('[1] Orchid meeting (mail: message-1)',result)
                self.assertIn('Monday',result)
                self.assertLessEqual(len(result),2400)
            finally:app.close()

if __name__ == "__main__":
    unittest.main()
