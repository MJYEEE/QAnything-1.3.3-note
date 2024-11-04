# 函数
- update_or_append_to_env()：更新或添加环境变量
- check_log_errors()：用于检查指定的日志文件中是否包含特定的错误信息
- check_folder_existence()：检测CustomLLM文件夹下$1文件夹是否存在 （宿主机上qanything的assets/custom_models）
- usage()：帮助信息，和run.sh中的一样
  
# 流程

## 1.设置默认参数和命令行参数
命令行参数是从run.sh中传过来的

## 2.验证MD5校验和
什么是MD5校验和：一种用于验证数据完整性的散列值
该处主要是验证和更新 FastChat 目录下的文件是否有变化，以决定是否需要重新安装依赖
```shell
checksum=$( \
    find /workspace/qanything_local/third_party/FastChat -type f \ 
    -exec md5sum {} + | awk '{print $1}' | sort | md5sum | awk '{print $1}' \
    )

```
- `find`：命令查找 FastChat 目录下的所有文件
- `-type f`：表示只查找文件
- `-exec`： 选项后面跟随的命令会对找到的每个文件执行
- `md5sum {}` 计算每个文件的 MD5 校验和，{} 是 find 命令的占位符，代表找到的每一个文件
- `|` 符号用于将前一个命令的输出传递给下一个命令
- `awk '{print $1}'`： 从 md5sum 的输出中提取每一行的第一个字段，$1 是校验和
- sort 对所有校验和进行排序，确保后续的 MD5 校验和计算是基于相同的文件顺序，以消除顺序变化导致的不同校验和
- 然后再次使用 awk 提取 md5sum 的输出的第一个字段，即计算得出的总体校验和
- 将最终计算出的校验和赋值给变量 checksum 

## 3.创建rerank的日志路径
暂时没什么重要分析

## 4.设置GPU_ID
设置接受参数里的GPU_ID，如果没有GPU2，则与GPU1相同

## 5.获取显卡型号和设置算力参数，之后设置后端
如果命令行没有设置后端参数，则使用默认值default，此时会根据显卡型号及算力，来自动调整后端。
如果使用的是30或40系列显卡则会根据算力和显存大小，从hf和vllm中选取backend。
否则还是default，即FastTransformer。我们用的是双3090，所以默认是vllm。.

## 6.根据显存选择模型大小
| 条件    | 输出信息   | 操作     |
|---------|-----------|--------|
| 显存 < 4GB      | 您当前的显存为 `$GPU1_MEMORY_SIZE` MiB 不足以部署本项目，建议升级到GTX 1050Ti或以上级别的显卡  | 退出程序 |
| 模型大小 = 0B   | 您当前的显存为 `$GPU1_MEMORY_SIZE` MiB 可以使用在线的OpenAI API     | -          |
| 显存 < 8GB      | 您当前的显存为 `$GPU1_MEMORY_SIZE` MiB 仅推荐使用在线的OpenAI API    | 如果模型大小 > 0B，输出并退出程序 |
| 8GB ≤ 显存 < 10GB    | 您当前的显存为 `$GPU1_MEMORY_SIZE` MiB 推荐部署1.8B的大模型，包括在线的OpenAI API | 如果模型大小 > 2B，输出并退出程序  |
| 10GB ≤ 显存 < 16GB   | 您当前的显存为 `$GPU1_MEMORY_SIZE` MiB，推荐部署3B及3B以下的模型，包括在线的OpenAI API | 如果模型大小 > 3B，输出并退出程序  |
| 16GB ≤ 显存 < 22GB   | 您当前的显存为 `$GPU1_MEMORY_SIZE` MiB 推荐部署小于等于7B的大模型   | 如果模型大小 > 7B，输出并退出程序   |
|                     | 根据 `$runtime_backend` 的值处理：     |      |
|                     | - 默认后端          | - 如果 GPU 系列存在                     |
|                     |   - 如果 GPU ID 相同：        | 输出并设置 `OFFCUT_TOKEN=1400`   |
|                     |   - 否则：     | 输出并设置 `OFFCUT_TOKEN=0`           |
|                     | - 否则：     | 输出并退出程序                         |
|                     | - Huggingface Transformers 后端       | 如果模型大小在 3B 和 7B 之间  |
|                     |   - 如果 GPU ID 相同：        | 输出并设置 `OFFCUT_TOKEN=2700`        |
|                     |   - 否则：           | 输出并设置 `OFFCUT_TOKEN=1800`        |
|                     | - 否则：          | 输出并设置 `OFFCUT_TOKEN=0`           |
|                     | - VLLM 后端                | 如果模型大小 > 3B   |
|                     |   - 输出：您的显存不足以使用vllm后端部署 `$model_size` 模型   | 退出程序  |
|                     |   - 否则：     | 输出并设置 `OFFCUT_TOKEN=0`           |
| 22GB ≤ 显存 < 24GB  | 您当前的显存为 `$GPU1_MEMORY_SIZE` MiB 推荐部署7B模型   | 如果模型大小 > 7B，输出并退出程序   |
|                    |                                                      | 设置 `OFFCUT_TOKEN=0` |
| 显存 > 24GB         | -            | 设置 `OFFCUT_TOKEN=0`     |


## 7.大模型中转服务启动
这个地方是有问题的，不清楚为什么在使用 run.sh 加上参数后，就会显示模型路径错误（暂时还没解决，老版本好像是没问题的）

根据runtime_backend来启动大模型中转服务
| 条件       | 操作说明     |
|------------|------------|
| `$runtime_backend` = "default"| 执行默认的 FastTransformer `runtime_backend`       |
|                               | - 判断 `gpu_id1` 和 `gpu_id2` 是否相同：            |
|                               |   - 相同：   |
|                               |     - 启动 Triton 服务器在 `$gpu_id1` 上运行，设置 `CUDA_VISIBLE_DEVICES`，并在后台运行  |
|                               |   - 不同：   |
|                               |     - 启动两个 Triton 服务器分别在 `$gpu_id1` 和 `$gpu_id2` 上，设置 `CUDA_VISIBLE_DEVICES`，并在后台运行  |
|                               | - 切换到 LLM 服务器目录并启动 Python 脚本  |
|                               | - 输出：大模型中转服务已就绪! (1/8)    |
| `$runtime_backend` != "default"| 启动嵌入和重排名的 Triton 服务器在 `$gpu_id2` 上 |
|                               | - 处理模型和环境变量的配置      |
|                               | - 启动 FastChat 相关的服务             |
|                               | - 在 `hf` 和 `vllm` 后端中选择：       |
|                               |   - `hf`：执行 `hf` `runtime_backend`               |
|                               |   - `vllm`：执行 `vllm` `runtime_backend`           |
|                               |   - `sglang`：执行 `sglang` `runtime_backend`       |
|                               |   - 其他情况：输出无效的 `runtime_backend` 选项并退出程序  |




## 8.后台启动 rerank_server.py、ocr_server.py以及 sanic_api.py
后台不挂起启动，并且将输出结果覆盖到对应的日志。
还会不断检测sanic_api.log有没有Starting worker字样，如果一段时间后没有，则超时处理。

## 9.设置后端日志
日志部分暂时不做解析

## 10.检查embedding服务和LLM服务是否启动和健康状态
只看源代码

## 11.检查日志中是否有错误
check_log_errors函数检查8中的后端 3个日志中有没有错误

## 12.运行结束
发出前端服务地址，并保持脚本运行