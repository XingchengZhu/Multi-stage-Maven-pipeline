# Multi-stage Maven Pipeline (Rocky 9.6 + Podman)

> 多阶段构建：在镜像的 **builder 阶段**完成 `mvn package`，在 **runtime 阶段**只带 JRE 和最终产物（镜像更瘦）。
> 支持 Jenkins 收集测试报告与使用 Podman 推送到 HTTP 私有仓库。

## 快速索引

* **多阶段 Dockerfile** → [`./Dockerfile`](./Dockerfile)
* **pom.xml** → [`./pom.xml`](./pom.xml)
* 运行端口：默认 `8080`
* 目标私有仓库：`10.29.230.150:31381`

> **提示**：多阶段 Dockerfile 会在镜像内部执行 `mvn package`，因此可以选择**不在宿主机先打包**。若你需要在 Jenkins 中收集测试报告，建议先本地执行 `mvn test` 再 `podman build`（见“推荐流水线”）。

---

## 推荐流水线（有测试报告）

先在宿主机跑测试（生成 surefire 报告），然后再交给多阶段 Dockerfile 在容器里做最终打包与构建镜像。

```bash
# 1) 单元测试（失败不阻断流水线）
mvn -B -U -fae -DskipTests=false -Dmaven.test.failure.ignore=true clean test
```

Jenkins 中 “JUnit test result” 使用下列通配收集报告：

```
**/target/surefire-reports/*.xml, **/target/failsafe-reports/*.xml
```

然后构建并推送镜像（由多阶段 Dockerfile 在容器内部完成打包与瘦身）：

```bash
podman login --tls-verify=false 10.29.230.150:31381 -u admin -p Admin123

# 多阶段构建：无需在宿主机先 package，镜像 builder 阶段会执行 mvn package
podman build --tls-verify=false \
  -t 10.29.230.150:31381/library/testrepo:multistage .

podman push --tls-verify=false 10.29.230.150:31381/library/testrepo:multistage
```

---

## 本地快速验证

```bash
# 查看镜像历史（确认确实是两阶段）
podman history 10.29.230.150:31381/library/testrepo:multistage

# 运行容器
podman run --rm -p 8080:8080 10.29.230.150:31381/library/testrepo:multistage
# 打开 http://localhost:8080
```

---

## 对齐与注意事项

* **JDK/JRE 版本对齐**

  * 多阶段 Dockerfile 的 `builder` 通常装 **JDK + Maven**，`runtime` 只装 **JRE**。
  * 若 `pom.xml` 使用 Java 8（`<java.version>1.8</java.version>`），建议在 **builder 阶段**使用 **JDK8** 或在 `maven-compiler-plugin` 中启用 `<release>8</release>`；否则用 JDK17 编译成 1.8 目标可能需要 bootclasspath/toolchain 配置。
  * 如需保持最稳妥：把 builder 阶段的 JDK 改为 **OpenJDK 1.8**；或在 `pom.xml` 的 `maven-compiler-plugin` 中改为：

    ```xml
    <configuration>
      <release>8</release>
      <encoding>${project.build.sourceEncoding}</encoding>
    </configuration>
    ```
* **HTTP 仓库**

  * 目前使用 `--tls-verify=false` 兼容 HTTP 或自签名证书。若改为受信 HTTPS，可移除此参数。
* **缓存与加速**

  * Dockerfile 中通常会 `COPY pom.xml` 后先执行 `dependency:go-offline` 以最大化依赖缓存层利用。
* **制品命名**

  * 建议在 `pom.xml` 中用 `<finalName>` 固定 JAR 名，便于 `Dockerfile` 在 runtime 阶段精确 `COPY` 或 `ENTRYPOINT` 指定。

---

## 常见问题

**1. Jenkins 找不到测试报告**
在测试阶段结束后调试：

```bash
pwd
find . -maxdepth 4 \( -name 'TEST-*.xml' -o -path '*/surefire-reports/*.txt' -o -name 'failsafe-summary.xml' \) -type f -print
```

确认生成了 `target/surefire-reports/*.xml`。

**2. 推送报 “server gave HTTP response to HTTPS client”**
对 `login/build/push` 全部加 `--tls-verify=false`。

**3. 镜像体积仍然较大**
确保 runtime 阶段只装 **JRE（headless 更轻）**，不要把 Maven/JDK 带到 runtime。

---

## 文件一览

* **多阶段 Dockerfile**：[`./Dockerfile`](./Dockerfile)

  * `FROM ... AS builder`：安装 JDK + Maven，`mvn package`
  * `FROM ...`（runtime）：只装 JRE，`COPY --from=builder` 拷贝可执行产物
* **pom.xml**：[`./pom.xml`](./pom.xml)

  * Spring Boot + Surefire（`failIfNoTests=false`）
  * Java 版本配置（确保与构建 JDK 对齐，见上文）

