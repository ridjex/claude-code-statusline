package cache

import (
	"encoding/json"
	"os"
	"path/filepath"
	"testing"
)

func TestProjectHash(t *testing.T) {
	// Must match bash: echo "tmp-statusline-test-project" | md5 -q | cut -c1-8
	// The hash includes the trailing newline from echo.
	hash := ProjectHash("/tmp/statusline-test-project")
	if len(hash) != 8 {
		t.Errorf("hash length = %d, want 8", len(hash))
	}
	// Deterministic
	if hash != ProjectHash("/tmp/statusline-test-project") {
		t.Error("hash not deterministic")
	}
	// Different dirs give different hashes
	h2 := ProjectHash("/tmp/other-project")
	if hash == h2 {
		t.Error("different dirs gave same hash")
	}
}

func TestReadModels(t *testing.T) {
	dir := t.TempDir()
	t.Setenv("XDG_CACHE_HOME", dir)
	cacheDir := filepath.Join(dir, "claude-code-statusline")
	_ = os.MkdirAll(cacheDir, 0o755)

	mc := ModelsCache{
		Models: []ModelEntry{
			{Model: "claude-opus-4-6-20250514", In: 549000, Out: 41200},
			{Model: "claude-sonnet-4-5-20250929", In: 180000, Out: 25000},
			{Model: "claude-haiku-4-5-20251001", In: 45000, Out: 15000},
		},
	}
	data, _ := json.Marshal(mc)
	_ = os.WriteFile(filepath.Join(cacheDir, "models-test-123.json"), data, 0o644)

	stats := ReadModels("test-123")
	if stats == nil {
		t.Fatal("ReadModels returned nil")
	}
	if stats.OpusIn != 549000 {
		t.Errorf("OpusIn = %d, want 549000", stats.OpusIn)
	}
	if stats.OpusOut != 41200 {
		t.Errorf("OpusOut = %d, want 41200", stats.OpusOut)
	}
	if stats.SonnetIn != 180000 {
		t.Errorf("SonnetIn = %d, want 180000", stats.SonnetIn)
	}
	if stats.SonnetOut != 25000 {
		t.Errorf("SonnetOut = %d, want 25000", stats.SonnetOut)
	}
	if stats.HaikuIn != 45000 {
		t.Errorf("HaikuIn = %d, want 45000", stats.HaikuIn)
	}
	if stats.HaikuOut != 15000 {
		t.Errorf("HaikuOut = %d, want 15000", stats.HaikuOut)
	}
}

func TestReadModelsNotFound(t *testing.T) {
	dir := t.TempDir()
	t.Setenv("XDG_CACHE_HOME", dir)
	if stats := ReadModels("nonexistent"); stats != nil {
		t.Error("expected nil for missing cache")
	}
}

func TestReadModelsEmpty(t *testing.T) {
	if stats := ReadModels(""); stats != nil {
		t.Error("expected nil for empty session ID")
	}
}

func TestReadCumulative(t *testing.T) {
	dir := t.TempDir()
	t.Setenv("XDG_CACHE_HOME", dir)
	cacheDir := filepath.Join(dir, "claude-code-statusline")
	_ = os.MkdirAll(cacheDir, 0o755)

	projData := `{"d1":{"cost":374},"d7":{"cost":3964},"d30":{"cost":7144}}`
	allData := `{"d1":{"cost":552},"d7":{"cost":4690},"d30":{"cost":12025}}`

	hash := ProjectHash("/tmp/statusline-test-project")
	_ = os.WriteFile(filepath.Join(cacheDir, "proj-"+hash+".json"), []byte(projData), 0o644)
	_ = os.WriteFile(filepath.Join(cacheDir, "all.json"), []byte(allData), 0o644)

	proj, all := ReadCumulative("/tmp/statusline-test-project")

	if proj == nil {
		t.Fatal("proj is nil")
	}
	if proj.D1 != 374 || proj.D7 != 3964 || proj.D30 != 7144 {
		t.Errorf("proj = %+v", proj)
	}

	if all == nil {
		t.Fatal("all is nil")
	}
	if all.D1 != 552 || all.D7 != 4690 || all.D30 != 12025 {
		t.Errorf("all = %+v", all)
	}
}

func TestReadCumulativeZero(t *testing.T) {
	dir := t.TempDir()
	t.Setenv("XDG_CACHE_HOME", dir)
	cacheDir := filepath.Join(dir, "claude-code-statusline")
	_ = os.MkdirAll(cacheDir, 0o755)

	zeroData := `{"d1":{"cost":0},"d7":{"cost":0},"d30":{"cost":0}}`
	hash := ProjectHash("/tmp/test")
	_ = os.WriteFile(filepath.Join(cacheDir, "proj-"+hash+".json"), []byte(zeroData), 0o644)
	_ = os.WriteFile(filepath.Join(cacheDir, "all.json"), []byte(zeroData), 0o644)

	proj, all := ReadCumulative("/tmp/test")
	if proj != nil {
		t.Error("zero-cost proj should return nil")
	}
	if all != nil {
		t.Error("zero-cost all should return nil")
	}
}

func TestReadCumulativeMissing(t *testing.T) {
	dir := t.TempDir()
	t.Setenv("XDG_CACHE_HOME", dir)

	proj, all := ReadCumulative("/tmp/nonexistent")
	if proj != nil {
		t.Error("missing proj should return nil")
	}
	if all != nil {
		t.Error("missing all should return nil")
	}
}
