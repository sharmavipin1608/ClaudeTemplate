# Java Conventions Overlay

Merged into `CONVENTIONS.md` by `bootstrap.sh` when stack is Java.

---

## Code Style — Java

- **Formatter:** Google Java Format or Checkstyle with project config; zero warnings policy
- **Naming:** classes PascalCase, methods and variables camelCase, constants UPPER_SNAKE_CASE, packages all-lowercase
- **No wildcard imports:** `import java.util.*` is banned; one class per import line
- **Type safety:** no raw types; no unchecked casts without a comment explaining why
- **Null handling:** prefer `Optional<T>` over returning `null` from public methods; annotate with `@Nullable` / `@NonNull` (JSR 305 or JetBrains) where `Optional` is impractical

## Folder Structure — Java

```
src/
  main/
    java/
      com/<org>/<project>/
        model/
        service/
        repository/
        controller/       ← HTTP layer, if applicable
        util/
    resources/
      application.properties
  test/
    java/
      com/<org>/<project>/
        service/          ← unit tests mirror main/ structure
        integration/      ← *IT.java files run by Failsafe
    resources/
pom.xml                   ← or build.gradle + settings.gradle
```

## Testing — Java

- **Runner:** JUnit 5 via Maven Surefire (`mvn test`) or Gradle (`./gradlew test`)
- **Coverage target:** 80% line and branch coverage; enforced by JaCoCo in CI
- **Test naming:** `<MethodUnderTest>_<Scenario>_<ExpectedResult>` e.g. `createUser_withDuplicateEmail_throwsConflictException`
- **Mocking:** Mockito; prefer constructor injection over field injection so tests do not need `@InjectMocks`
- **Assertions:** AssertJ `assertThat(...)` — more readable failure output than raw JUnit `assertEquals`
- **Integration tests:** suffix `*IT.java`; run separately via Maven Failsafe or a Gradle `integrationTest` source set; use a real database (Testcontainers) not H2

## Dependencies — Java

- Declare all versions in `<dependencyManagement>` (Maven) or `gradle/libs.versions.toml` (Gradle); never use version ranges (`[1.0,2.0)`)
- Separate test-scoped dependencies (`<scope>test</scope>` in Maven, `testImplementation` in Gradle)
- Run `mvn dependency-check:check` or `./gradlew dependencyCheckAnalyze` in CI for CVE scanning
