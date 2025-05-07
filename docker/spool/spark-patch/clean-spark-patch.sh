set -euo pipefail

cd ./spark

echo "�~_�� Cleaning Spark build..."

export MAVEN_OPTS="-Xss64m -Xmx2g -XX:ReservedCodeCacheSize=1g"

./build/mvn clean

echo "�~_~W~Q�~O Removing stale targets..."
rm -rf assembly/target core/target examples/target \
       external/target graphx/target mllib/target \
       streaming/target repl/target sql/target \
       resource-managers/target launcher/target \
       output/ jars/ *.log || true

echo "�~_~T� Building Spark with all assemblies..."
./build/mvn -DskipTests clean package

echo "�~_~S� Validating expected JARs..."
ls -l jars/scala-library*.jar || { echo "�~]~L Scala library missing!"; exit 1; }

echo "�~_~T~M Checking for patched logging string..."
if find . -name "*.class" -exec strings {} \; | grep -q "Original JVM launch command:"; then
    echo "�~\~E Found expected patch: �~_~T� Original JVM launch command"
else
    echo "�~]~L Patch missing: �~_~T� Original JVM launch command NOT found!"
    exit 1
fi

echo "�~_~Z� Verifying no stale logs remain..."
if find . -name "*.class" -exec strings {} \; | grep -q "Launch command:"; then
    echo "�~]~L Found stale log: 'Launch command:' �~@~T remove or update this"
    exit 1
else
    echo "�~\~E No stale log: 'Launch command:'"
fi

echo "�~_~N~I Build and validation complete."
