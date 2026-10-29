import unittest
from pathlib import Path
from types import SimpleNamespace
import sys


sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from app import _segment_payload, sanitize_filename  # noqa: E402


class FilenameTests(unittest.TestCase):
    def test_removes_path_and_unsafe_characters(self):
        self.assertEqual(sanitize_filename("..%2Flesson%3F01.mp3"), "lesson_01.mp3")

    def test_falls_back_for_empty_name(self):
        self.assertEqual(sanitize_filename("..."), "audio.mp3")


class SegmentTests(unittest.TestCase):
    def test_preserves_word_timestamps(self):
        segment = SimpleNamespace(
            start=1.0,
            end=2.5,
            text=" Hello world.",
            words=[
                SimpleNamespace(start=1.0, end=1.4, word=" Hello"),
                SimpleNamespace(start=1.5, end=2.2, word=" world."),
            ],
        )
        payload = _segment_payload(segment)
        self.assertEqual(payload["text"], "Hello world.")
        self.assertEqual(payload["words"][0]["startTime"], 1.0)
        self.assertEqual(payload["words"][1]["endTime"], 2.2)

    def test_creates_fallback_word(self):
        segment = SimpleNamespace(start=3.0, end=4.0, text=" Test", words=[])
        payload = _segment_payload(segment)
        self.assertEqual(len(payload["words"]), 1)
        self.assertEqual(payload["words"][0]["text"], "Test")


if __name__ == "__main__":
    unittest.main()
