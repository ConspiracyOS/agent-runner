package contracts

import (
	"path/filepath"
	"runtime"
	"testing"
)

func TestLoadDir_SystemContracts(t *testing.T) {
	// Find the project root relative to this test file
	_, thisFile, _, _ := runtime.Caller(0)
	projectRoot := filepath.Join(filepath.Dir(thisFile), "..", "..")
	contractsDir := filepath.Join(projectRoot, "configs", "default", "contracts")

	contracts, err := LoadDir(contractsDir)
	if err != nil {
		t.Fatal(err)
	}

	if len(contracts) != 6 {
		t.Errorf("LoadDir returned %d contracts, want 6", len(contracts))
	}

	// Verify all have IDs and are detective type
	for _, c := range contracts {
		if c.ID == "" {
			t.Error("contract has empty ID")
		}
		if c.Type != "detective" {
			t.Errorf("contract %s: type = %q, want detective", c.ID, c.Type)
		}
	}
}
