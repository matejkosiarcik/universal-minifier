# Helper Makefile to group scripts for development

MAKEFLAGS += --warn-undefined-variables
SHELL := /bin/sh
.SHELLFLAGS := -ec
PROJECT_DIR := $(abspath $(dir $(MAKEFILE_LIST)))

.POSIX:
.SILENT:

.DEFAULT: all
.PHONY: all
all: clean bootstrap build test docker-build docker-multibuild

.PHONY: bootstrap
bootstrap:
	# NodeJS
	printf '%s\n%s\n' cli minifiers | while read -r dir; do \
		npm ci --no-save --no-progress --no-audit --quiet --prefix "$$dir" && \
	true ; done

	# Python
	printf '%s\n' minifiers | while read -r dir; do \
		cd "$(PROJECT_DIR)/$$dir" && \
		PIP_DISABLE_PIP_VERSION_CHECK=1 \
			python3 -m pip install --requirement requirements.txt --target "$$PWD/python" --quiet --upgrade && \
	true ; done

	# Gitman package
	cd "$(PROJECT_DIR)/docker-utils/dependencies/gitman" && \
	PIP_DISABLE_PIP_VERSION_CHECK=1 \
		python3 -m pip install --requirement requirements.txt --target "$$PWD/python" --quiet --upgrade

	# Gitman repositories
	printf '%s\n' bash-minifier | while read -r dir; do \
		cd "$(PROJECT_DIR)/minifiers/gitman/$$dir" && \
		PATH="$(PROJECT_DIR)/docker-utils/dependencies/gitman/python/bin:$$PATH" \
		PYTHONPATH="$(PROJECT_DIR)/docker-utils/dependencies/gitman/python" \
		PYTHONDONTWRITEBYTECODE=1 \
			gitman install --quiet --force && \
	true ; done

.PHONY: test
test:
	npm --prefix cli test

.PHONY: build
build:
	npm --prefix cli run build

.PHONY: clean
clean:
	rm -rf \
		"$(PROJECT_DIR)/cli/dist" \
		"$(PROJECT_DIR)/cli/node_modules" \
		"$(PROJECT_DIR)/minifiers/node_modules" \
		"$(PROJECT_DIR)/minifiers/python" \

.PHONY: docker-build
docker-build:
	time docker build . --tag matejkosiarcik/universal-minifier:dev

.PHONY: docker-multibuild
docker-multibuild:
	printf '%s\n%s\n%s\n%s\n%s\n%s\n%s\n' 386 amd64 arm/v5 arm/v7 arm64/v8 ppc64le s390x | \
		while read -r arch; do \
			printf 'Building for linux/%s:\n' "$$arch" && \
			time docker build . --tag "matejkosiarcik/universal-minifier:dev-$$(printf '%s' "$$arch" | tr '/' '-')" --platform "linux/$$arch" && \
		true; done
