#!/bin/bash 

set -x

time spark-submit --class org.apache.spark.shuffle.examples.SparkSortApp /opt/spark/jars/spark-weave-shuffle-assembly-0.1.0.jar spark 2000000 5 5


time spark-submit --class org.apache.spark.shuffle.examples.SparkSortApp /opt/spark/jars/spark-weave-shuffle-assembly-0.1.0.jar sparkmr 2000000 5 5


time spark-submit --class org.apache.spark.shuffle.examples.SparkSortApp /opt/spark/jars/spark-weave-shuffle-assembly-0.1.0.jar sparkmanual 2000000 5 5


time spark-submit --class org.apache.spark.shuffle.examples.SparkSortApp /opt/spark/jars/spark-weave-shuffle-assembly-0.1.0.jar weave 2000000 5 5


time spark-submit --class org.apache.spark.shuffle.examples.SparkSortApp /opt/spark/jars/spark-weave-shuffle-assembly-0.1.0.jar columnsort 2000000 5 5
