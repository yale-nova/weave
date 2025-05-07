# Makefile for Spark Weave Shuffle Experiments

.PHONY: build-fatjar build-sampling datasets test

build-fatjar:
	@echo "🛠️ Building fat JAR..."
	sbt assembly

build-sampling:
	@echo "🛠️ Building SamplingJob..."
	sbt "runMain SamplingJob"

datasets:
	@echo "⬇️ Downloading datasets..."
	bash scripts/download_datasets.sh

test:
	@echo "🧪 Running test pipeline..."
	bash scripts/test-pipeline.sh

cp: 
	cp -r /opt/private-repos/spark-weave-shuffle .
