# Convenience wrappers. Usage: make plan ENV=nonprod
ENV ?= nonprod
TF   = terraform -chdir=terraform/environments/$(ENV)

.PHONY: fmt validate init plan apply destroy lint docs charts lite-validate lite-up lite-down lite-smoke

fmt:
	terraform fmt -recursive terraform

# Validate every module + environment without touching a backend or AWS.
validate:
	@for d in terraform/bootstrap terraform/environments/nonprod terraform/environments/prod terraform/addons/nonprod terraform/addons/prod; do \
		echo "==> $$d"; \
		terraform -chdir=$$d init -backend=false -input=false >/dev/null && \
		terraform -chdir=$$d validate || exit 1; \
	done

# Lint + render the Helm chart for all workloads (needs helm; kubeconform optional).
charts:
	scripts/render-charts.sh

init:
	$(TF) init -backend-config=backend.hcl

plan: init
	$(TF) plan -out=tfplan

apply:
	$(TF) apply tfplan

destroy:
	$(TF) destroy

# Static analysis (install once: brew install tflint checkov)
lint:
	tflint --recursive
	checkov -d terraform --quiet --compact

# --- Lite edition (free tier / local) -----------------------------------------
lite-validate:
	shellcheck lite/scripts/*.sh
	terraform -chdir=terraform/lite init -backend=false
	terraform -chdir=terraform/lite validate
	terraform fmt -check terraform/lite
	@python3 -c "import yaml" 2>/dev/null || { echo "PyYAML missing: pip install pyyaml (skipping YAML parse)"; exit 0; }; \
	python3 -c "import yaml,glob; [list(yaml.safe_load_all(open(f))) for f in glob.glob('lite/**/*.yaml', recursive=True)]; print('lite yaml ok')"

lite-up:
	lite/scripts/local-up.sh

lite-down:
	lite/scripts/local-down.sh

lite-smoke:
	lite/scripts/smoke-test.sh
