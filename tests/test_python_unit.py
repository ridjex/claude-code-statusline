"""Unit tests for Python engine formatting functions."""
import sys
import os

# Add the python engine to path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "engines", "python"))
import statusline


class TestFmtK:
    def test_zero(self):
        assert statusline.fmt_k(0) == "0"

    def test_small(self):
        assert statusline.fmt_k(523) == "523"
        assert statusline.fmt_k(999) == "999"

    def test_thousands(self):
        assert statusline.fmt_k(1000) == "1.0k"
        assert statusline.fmt_k(1234) == "1.2k"
        assert statusline.fmt_k(9999) == "10.0k"

    def test_ten_thousands(self):
        assert statusline.fmt_k(10000) == "10k"
        assert statusline.fmt_k(45231) == "45k"

    def test_millions(self):
        assert statusline.fmt_k(1000000) == "1.0M"
        assert statusline.fmt_k(1234567) == "1.2M"


class TestFmtCost:
    def test_zero(self):
        assert statusline.fmt_cost(0) == "$0.00"

    def test_cents(self):
        assert statusline.fmt_cost(0.12) == "$0.12"

    def test_dollars(self):
        assert statusline.fmt_cost(1.0) == "$1.0"
        assert statusline.fmt_cost(8.42) == "$8.4"

    def test_tens(self):
        assert statusline.fmt_cost(10.0) == "$10"
        assert statusline.fmt_cost(374.0) == "$374"

    def test_thousands(self):
        assert statusline.fmt_cost(1000.0) == "$1.0k"
        assert statusline.fmt_cost(1800.0) == "$1.8k"


class TestShortenBranch:
    def test_feature(self):
        assert statusline.shorten_branch("feature/login") == "\u2605login"
        assert statusline.shorten_branch("feat/auth") == "\u2605auth"

    def test_fix(self):
        assert statusline.shorten_branch("fix/crash") == "\u2726crash"

    def test_no_prefix(self):
        assert statusline.shorten_branch("main") == "main"

    def test_empty(self):
        assert statusline.shorten_branch("") == ""


class TestTrunc:
    def test_short(self):
        assert statusline.trunc("hello", 10) == "hello"

    def test_exact(self):
        assert statusline.trunc("hello", 5) == "hello"

    def test_long(self):
        assert statusline.trunc("hello world", 5) == "hell\u2026"

    def test_unicode(self):
        result = statusline.trunc("日本語テスト", 4)
        assert result == "日本語\u2026"
