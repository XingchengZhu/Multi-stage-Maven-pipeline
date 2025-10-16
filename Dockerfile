# ====== Build Stage ======
FROM 10.29.230.150:31381/library/m.daocloud.io/docker.io/rockylinux/rockylinux:9.6.20250531 AS builder

# 基础工具 + OpenJDK 17 + Maven
RUN dnf clean all && \
    dnf -y --nobest --allowerasing update && \
    dnf -y --nobest --allowerasing install \
      java-17-openjdk-devel maven tzdata git which tar gzip && \
    dnf clean all

# 时区
ENV TZ=Asia/Shanghai
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

WORKDIR /app

# 先拷 POM 以利用依赖缓存
COPY pom.xml ./
RUN mvn -B -U -q -DskipTests=true dependency:go-offline

# 再拷源码
COPY src ./src

# 打包（生成 target/*.jar）
RUN mvn -B -U -DskipTests=true clean package

# ====== Runtime Stage ======
FROM 10.29.230.150:31381/library/m.daocloud.io/docker.io/rockylinux/rockylinux:9.6.20250531

# 仅安装运行所需的 JRE（headless 更轻）
RUN dnf clean all && \
    dnf -y --nobest --allowerasing update && \
    dnf -y --nobest --allowerasing install \
      java-17-openjdk-headless tzdata && \
    dnf clean all

ENV TZ=Asia/Shanghai
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

WORKDIR /app

# 允许外部以构建参数覆写 Jar 路径（默认匹配单个可执行 JAR）
ARG JAR_PATH=/app/target/*-SNAPSHOT.jar
COPY --from=builder ${JAR_PATH} /app/app.jar

EXPOSE 8080
ENTRYPOINT ["java","-jar","/app/app.jar"]
