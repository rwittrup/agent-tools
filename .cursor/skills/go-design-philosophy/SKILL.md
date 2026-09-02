---
name: go-design-philosophy
description: Go-specific design and testing conventions—idiomatic Go, test packages, public API testing. Use when writing or reviewing Go code in call-handler or other Go services.
---

# Go Design Philosophy

Go specifics:
- follow idiomatic Go, borrowing styles and approaches from the Golang standard library
- when creating new packages in go, tests for those files should be in a test package. Example: for package name "languages", tests would be in "languages_test"
- do not create or export methods only for testing - test against the public API and do not expose functionality only for testing
