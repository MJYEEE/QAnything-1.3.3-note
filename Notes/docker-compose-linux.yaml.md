# 容器列表
这个 docker-compose.yaml 文件定义了多个服务，主要用于构建一个包含 Elasticsearch、Milvus、MySQL 和 QAnything 的本地开发环境

# yaml中 volumes 
作用是 指定挂载模型目录和工作目录
具体用法如下：

以 `${DOCKER_VOLUME_DIRECTORY:-.}/assets/custom_models:/model_repos/CustomLLM` 为例：
- `${DOCKER_VOLUME_DIRECTORY:-.}`：
  - 这是一个参数替换的语法，用于获取环境变量的值。
  - DOCKER_VOLUME_DIRECTORY 是一个环境变量名。
  - `:-` 表示如果 DOCKER_VOLUME_DIRECTORY 没有被设置或为空，则使用`.`（当前目录）作为默认值。
- `/`:
  - 这是挂载路径的分隔符，用于分隔宿主机目录和容器目录。
- `:/workspace/qanything_local/`:
  - 这是容器内部的目录路径，表示将宿主机目录挂载到容器内的`/workspace/qanything_local/`路径。

# yaml中 healthcheck
是 Docker Compose 中用于定义容器健康检查的配置项。通过健康检查，Docker 可以监控容器的状态，确保其正常运行。如果健康检查失败，Docker 可以自动重启容器，从而提高应用的可靠性和稳定性

每个容器中的 healthcheck 配置项通常包含以下几个部分：

- test：
  - 这是执行健康检查的命令。可以是 shell 命令或其他执行命令的方式（如 CMD）。
如果命令返回状态码为 0，表示健康检查通过；返回非零状态码则表示检查失败。
- interval：
  - 定义健康检查的执行间隔，单位是时间（如秒）。这是指 Docker 在上一个健康检查完成后多久进行下一次检查。
- timeout：
  - 定义健康检查命令的超时时间。如果健康检查命令在指定的超时时间内没有完成，将被视为失败。
- retries：
  - 定义在标记容器为不健康之前，健康检查失败的最大次数。如果健康检查失败次数超过此值，容器将被标记为不健康。
- start_period（可选）：
  - 在容器启动后，Docker 将在此期间内忽略健康检查的失败。这对于允许服务在启动时有足够的时间进行初始化非常有用。
  
# yaml中的 tty
- 当 tty: true 时，Docker 会为容器分配一个伪终端（pseudo-terminal），使得容器可以像本地终端一样处理输入和输出。
- 这对于需要交互式控制的应用程序（如命令行工具）非常重要，因为它允许用户在容器中与应用程序进行交互。

# yaml中的 stdin_open
stdin_open: true 保持标准输入开放：
- 设置 stdin_open: true 使得容器的标准输入保持开放，允许用户向容器发送输入。
- 这通常与 tty: true 一起使用，以便能够在容器内交互地输入命令或数据。

# es-container-local
Elasticsearch 是在 Apache Lucene 上构建的分布式搜索和分析引擎
# milvus本地部署容器群
milvus本地部署需要用到以下三个容器
- etcd-container-local
- milvus-minio-local
- milvus-standalone-local

# mysql-container-local
这个没什么好解释的 mysql数据库 
如果你有一些额外的服务用到了该数据库，可以将端口映射到宿主机，否则在无法访问
已经将 主机上的/volumes/mysql映射到了/var/lib/mysql

# qanything-container-local
容器内运行脚本
```shell
/bin/bash -c 'if [ "${LLM_API}" = "local" ]; \
    then /workspace/qanything_local/scripts/run_for_local_option.sh \
    -c $LLM_API \
    -i $DEVICE_ID \ 
    -b $RUNTIME_BACKEND \ 
    -m $MODEL_NAME \ 
    -t $CONV_TEMPLATE \
    -p $TP \ 
    -r $GPU_MEM_UTILI; \
    else /workspace/qanything_local/scripts/run_for_cloud_option.sh \
    -c $LLM_API \
    -i $DEVICE_ID \ 
    -b $RUNTIME_BACKEND; \ 
    fi; \ 
    while true; do sleep 5; done'
```
- `/bin/bash -c`:
  - `/bin/bash`：指定使用 Bash shell 来执行命令。
  - `-c`：表示接下来是一个命令字符串，Bash 将执行这个字符串中的内容。

接下来是local模式和cloud模式的区别

- ${LLM_API} 在 run.sh中已经设置
- `/workspace/qanything_local/scripts/run_for_local_option.sh`：
  - 这是一个脚本，用于在 local 模式下运行 QAnything，已经从主机上的qanything文件夹映射到容器内了
  - 后面便是一些该脚本的具体参数，我们到后面直接到脚本上查看
- `run_for_cloud_option.sh`同上

结束部分：
- `while true; do sleep 5; done`
  - 这个循环会一直运行，持续睡眠 5 秒。
  - 这样做的目的是保持容器持续运行，不会因脚本执行完毕而退出。容器必须保持在运行状态，以便能接受请求或进行进一步处理
  

# yaml中的 netnetworks
这是 Docker Compose 文件中的一个顶级配置项，用于定义网络设置。通过网络配置，用户可以控制容器间的通信方式。

网络的作用
- 服务间通信：所有连接到同一个网络的容器可以通过容器名称直接相互通信，而不需要通过映射到宿主机的端口。这意味着，如果某个容器想要与另一个容器（例如，Elasticsearch 与 Milvus）进行通信，只需使用另一个容器的名称即可。(例如，容器 A 可以通过访问 `容器_B:端口` 来访问容器 B 的服务) (如果你将容器对应端口映射到了主机上，也可以直接通过主机ip访问)
- 隔离：网络可以用于隔离不同的服务组，防止不必要的通信。例如，可以为前端和后端服务创建不同的网络，以限制它们之间的访问。