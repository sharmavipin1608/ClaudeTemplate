# Java Stack Overlay

Appended to agent definitions by `bootstrap.sh` when stack is Java. Extends base agent rules with Java-specific commands and patterns.

---

## Coder — Java additions

- **Build tool:** Maven (`mvn`) or Gradle (`./gradlew`) — match whichever the project uses; never mix them
- **Formatter:** Google Java Format or Checkstyle — run before committing; config in `checkstyle.xml` or `.editorconfig`
- **Type safety:** no raw types (`List` without `<T>`); no unchecked casts without a suppression comment explaining why
- **Tests:** use JUnit 5 (`@Test`, `@BeforeEach`, `@AfterEach`); test classes in `src/test/java/` mirroring `src/main/java/` structure
- **TDD command:** `mvn test -Dtest=ClassName#methodName` or `./gradlew test --tests "pkg.ClassName.methodName"`
- **Imports:** no wildcard imports (`import java.util.*`); enforce via Checkstyle `AvoidStarImport`
- **Dependency pinning:** declare explicit versions in `pom.xml` `<dependencyManagement>` or `gradle/libs.versions.toml`; no floating version ranges

## Tester — Java additions

- **Test runner:** `mvn test` or `./gradlew test`
- **Coverage:** JaCoCo; fail below 80%: configure `<limit>` in `jacoco-maven-plugin` or `jacocoTestCoverageVerification` in Gradle
- **Unit isolation:** use Mockito for mocking; prefer constructor injection so mocks can be passed directly without `@InjectMocks`
- **Integration tests:** separate from unit tests via Maven Failsafe plugin (`*IT.java`) or Gradle `integrationTest` source set
- **Assertions:** use AssertJ (`assertThat(...)`) over raw JUnit assertions — more readable failure messages
- **Parameterized tests:** use `@ParameterizedTest` with `@MethodSource` or `@CsvSource` — do not duplicate test methods for similar inputs

## Security — Java additions

- Check for string concatenation into SQL queries (`"SELECT ... WHERE id = " + userInput`) → SQL injection; require PreparedStatement or JPA named parameters
- Check for `Runtime.exec()` or `ProcessBuilder` with user-controlled input → command injection
- Check for Java deserialization: `ObjectInputStream.readObject()` on untrusted data → arbitrary code execution
- Check for XML parsing without disabling external entities (XXE): `DocumentBuilderFactory` without `setFeature(XMLConstants.FEATURE_SECURE_PROCESSING, true)`
- Check for hardcoded secrets (passwords, API keys, tokens) in source or `application.properties`
- Check for `@SuppressWarnings("unchecked")` on casts that involve user-controlled data
- Check `pom.xml` or `build.gradle` dependencies for known CVEs (flag for manual review via `mvn dependency-check:check` or `./gradlew dependencyCheckAnalyze`)
