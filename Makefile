# usage: make help
.DEFAULT_GOAL := help


#check: ## run formatting checks
#	cd .. && make check


version: ## create a new version of the project
	@bash scripts/gen_git_version.sh 

switch: ## switch to the new version (requires exported MY_VERSION, e.g. export MY_VERSION=… && make switch)
	@export MY_VERSION=$$(cat .version | xargs) && test -n "$$MY_VERSION" || (echo >&2 "MY_VERSION is not set; export it before running make switch" && exit 1) && echo "MY_VERSION=$$MY_VERSION" && git switch -c version/$$MY_VERSION

help: ## display this help message
	@echo "Usage: make <target>"
	@echo "Targets:"
	@echo "  version - create a new version of the project"
	@echo "  help - display this help message"