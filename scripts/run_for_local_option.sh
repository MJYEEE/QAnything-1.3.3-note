#!/bin/bash
# 本脚本是在qanything容器中运行的
# 更新或添加环境变量
update_or_append_to_env() {
  local key=$1
  local value=$2
  local env_file="/workspace/qanything_local/.env"

  # 检查键是否存在于.env文件中
  if grep -q "^${key}=" "$env_file"; then
    # 如果键存在，则更新它的值
    sed -i "/^${key}=/c\\${key}=${value}" "$env_file"
  else
    # 如果键不存在，则追加键值对到文件
    echo "${key}=${value}" >> "$env_file"
  fi
}

# 用于检查指定的日志文件中是否包含特定的错误信息
check_log_errors() {
    local log_file=$1  # $1表示将第一个参数赋值给变量log_file，表示日志文件的路径 # local 关键字用于声明一个局部变量

    # 检查日志文件是否存在
    if [[ ! -f "$log_file" ]]; then
        echo "指定的日志文件不存在: $log_file"
        return 1
    fi

    # 使用grep命令检查"core dumped"或"Error"的存在
    # -C 5表示打印匹配行的前后各5行
    local pattern="core dumped|Error|error"
    if grep -E -C 5 "$pattern" "$log_file"; then
        echo "检测到错误信息，请查看上面的输出。"
        exit 1
    else
        echo "$log_file 中未检测到明确的错误信息。请手动排查 $log_file 以获取更多信息。"
    fi
}

# 检测CustomLLM文件夹下$1文件夹是否存在
# 检测本地模型是否存在
check_folder_existence() {
  if [ ! -d "/model_repos/CustomLLM/$1" ]; then
    echo "The $1 folder does not exist under QAnything/assets/custom_models/. Please check your setup."
    echo "在QAnything/assets/custom_models/下不存在$1文件夹。请检查您的模型文件。"
    exit 1
  fi
}

# 将当前教程名称赋值给script_name  $0表示当前脚本的路径，basename 命令用于提取路径中的文件名部分
script_name=$(basename "$0") 

# 帮助信息 和 run.sh中的一样 参数如下
# -c : 选项 {local, cloud} 指定 llm API 模式，默认为 'local'。如果设置为 '-c cloud'，请先在 run.sh 中手动将环境 {OPENAI_API_KEY, OPENAI_API_BASE, OPENAI_API_MODEL_NAME, OPENAI_API_CONTEXT_LENGTH} 设置为 .env
# -i <device_id> : 用于指定要使用的GPU设备ID。例如，-i 0 指定使用第一块GPU设备
# -b <runtime_backend> : 用于指定LLM推理后端，可选项有{default,hf,vllm}
# -m <model_name> : 指定参数使用 FastChat 服务 API 加载 LLM 模型的路径，options={Qwen-7B-Chat, deepseek-llm-7b-chat, ...}
# -t <conv_template> : 使用FastChat服务API时根据LLM模型指定对话模板参数，options={qwen-7b-chat, deepseek-chat, ...}
# -p <tensor_parallel> : 使用选项{1, 2} 在使用 FastChat 服务 API 时为 vllm 后端设置张量并行参数，默认 tensor_parallel=1
# -r <gpu_memory_utilization> : 使用 FastChat 服务 API 时为 vllm 后端指定参数 gpu_memory_utilization (0,1]，默认 gpu_memory_utilization=0.81
# -h : 显示帮助使用信息。有关更多信息，请参阅 docs/QAnything_Startup_Usage_README.md
usage() {
  echo "Usage: $script_name [-c <llm_api>] [-i <device_id>] [-b <runtime_backend>] [-m <model_name>] [-t <conv_template>] [-p <tensor_parallel>] [-r <gpu_memory_utilization>] [-h]"
  echo "  -c : Options {local, cloud} to specify the llm API mode, default is 'local'. If set to '-c cloud', please mannually set the environments {OPENAI_API_KEY, OPENAI_API_BASE, OPENAI_API_MODEL_NAME, OPENAI_API_CONTEXT_LENGTH} into .env fisrt in run.sh"
  echo "  -i <device_id>: Specify argument GPU device_id"
  echo "  -b <runtime_backend>: Specify argument LLM inference runtime backend, options={default, hf, vllm}"
  echo "  -m <model_name>: Specify argument the path to load LLM model using FastChat serve API, options={Qwen-7B-Chat, deepseek-llm-7b-chat, ...}"
  echo "  -t <conv_template>: Specify argument the conversation template according to the LLM model when using FastChat serve API, options={qwen-7b-chat, deepseek-chat, ...}"
  echo "  -p <tensor_parallel>: Use options {1, 2} to set tensor parallel parameters for vllm backend when using FastChat serve API, default tensor_parallel=1"
  echo "  -r <gpu_memory_utilization>: Specify argument gpu_memory_utilization (0,1] for vllm backend when using FastChat serve API, default gpu_memory_utilization=0.81"
  echo "  -h: Display help usage message"
  exit 1
}

# 设置初始参数
llm_api="local"
device_id="0"
runtime_backend="default"
model_name=""
conv_template=""
tensor_parallel=1
gpu_memory_utilization=0.81

# 解析命令行参数
while getopts ":c:i:b:m:t:p:r:h" opt; do
  case $opt in
    c) llm_api=$OPTARG ;;
    i) device_id=$OPTARG ;;
    b) runtime_backend=$OPTARG ;;
    m) model_name=$OPTARG ;;
    t) conv_template=$OPTARG ;;
    p) tensor_parallel=$OPTARG ;;
    r) gpu_memory_utilization=$OPTARG ;;
    h) usage ;;
    *) usage ;;
  esac
done

echo "llm_api is set to [$llm_api]"
echo "device_id is set to [$device_id]"
echo "runtime_backend is set to [$runtime_backend]"
echo "model_name is set to [$model_name]"
echo "conv_template is set to [$conv_template]"
echo "tensor_parallel is set to [$tensor_parallel]"
echo "gpu_memory_utilization is set to [$gpu_memory_utilization]"


# 验证和更新 FastChat 目录下的文件是否有变化，以决定是否需要重新安装依赖
# 获取默认的 MD5 校验和
default_checksum=$(cat /workspace/qanything_local/third_party/checksum.config)
# 计算FastChat文件夹下所有文件的 MD5 校验和 该行代码具体解析请看对应md文件
checksum=$(find /workspace/qanything_local/third_party/FastChat -type f -exec md5sum {} + | awk '{print $1}' | sort | md5sum | awk '{print $1}')
echo "checksum $checksum"
echo "default_checksum $default_checksum"
# 检查两个校验和是否相等，如果不相等则表示 third_party/FastChat/fastchat/conversation.py 注册了新的 conv_template, 则需重新安装依赖
if [ "$default_checksum" != "$checksum" ]; then
    cd /workspace/qanything_local/third_party/FastChat && pip install -e .
    checksum=$(find /workspace/qanything_local/third_party/FastChat -type f -exec md5sum {} + | awk '{print $1}' | sort | md5sum | awk '{print $1}') && echo "$checksum" > /workspace/qanything_local/third_party/checksum.config
fi

# 检查是否安装了vllm，如果没有则安装FastChat下所有需要的东西
install_deps=$(pip list | grep vllm)
if [[ "$install_deps" != *"vllm"* ]]; then
    echo "vllm deps not found"
    cd /workspace/qanything_local/third_party/FastChat && pip install -e .
    checksum=$(find /workspace/qanything_local/third_party/FastChat -type f -exec md5sum {} + | awk '{print $1}' | sort | md5sum | awk '{print $1}') && echo "$checksum" > /workspace/qanything_local/third_party/checksum.config
fi

mkdir -p /model_repos/QAEnsemble_base /model_repos/QAEnsemble_embed_rerank && mkdir -p /workspace/qanything_local/logs/debug_logs && mkdir -p /workspace/qanything_local/logs/qa_logs
if [ ! -L "/model_repos/QAEnsemble_base/base" ]; then
  # ln -s表示创建软链接，类似windows下的快捷方式
  # 在/model_repos/QAEnsemble_abse下创建一个名为 base 的符号链接，该符号链接指向 /model_repos/QAEnsemble/base 目录。 . ：这表示当前目录，即在当前目录下创建符号链接
  cd /model_repos/QAEnsemble_base && ln -s /model_repos/QAEnsemble/base .
fi

if [ ! -L "/model_repos/QAEnsemble_embed_rerank/rerank" ]; then
  cd /model_repos/QAEnsemble_embed_rerank && ln -s /model_repos/QAEnsemble/rerank .
fi

if [ ! -L "/model_repos/QAEnsemble_embed_rerank/embed" ]; then
  cd /model_repos/QAEnsemble_embed_rerank && ln -s /model_repos/QAEnsemble/embed .
fi

# qanything_local是宿主机上的qanything文件夹，映射到了容器内
cd /workspace/qanything_local

# 设置默认值
default_gpu_id1=0
default_gpu_id2=0

# 检查环境变量GPUID1是否存在，并读取其值或使用默认值
if [ -z "${GPUID1}" ]; then
    gpu_id1=$default_gpu_id1
else
    gpu_id1=${GPUID1}
fi

# 检查环境变量GPUID2是否存在，并读取其值或使用默认值
if [ -z "${GPUID2}" ]; then
    gpu_id2=$default_gpu_id2
else
    gpu_id2=${GPUID2}
fi
echo "GPU ID: $gpu_id1, $gpu_id2"

# 判断硬件条件与启动参数是否匹配
# 获取显卡型号
gpu_model=$(nvidia-smi --query-gpu=gpu_name --format=csv,noheader,nounits -i $gpu_id1)
# 从GPU型号中提取基本型号用于模糊匹配
base_gpu_model=$(echo $gpu_model | grep -o '^[^-]*')
# nvidia RTX 30系列或40系列或A系列，比如A10，A30，A30，A100，A800
gpu_series=$(echo $gpu_model | grep -oP '(RTX\s*(30|40)|A(10|30|40|100|800))')
#if ! command -v jq &> /dev/null; then
#    echo "Error: jq 命令不存在，请使用 sudo apt update && sudo apt-get install jq 安装，再重新启动。"
#    exit 1
#fi
# compute_capability=$(jq -r ".[\"$base_gpu_model\"]" /workspace/qanything_local/scripts/gpu_capabilities.json)
# 执行Python脚本，传入设备号，并捕获输出
compute_capability=$(python3 scripts/get_cuda_capability.py $gpu_id1) # 获取cuda主版本号和次版本号
status=$?  # 获取Python脚本的退出状态码 （0表示成功）
if [ $status -ne 0 ]; then # 如果status不等于0，则表示Python脚本执行出错
    echo "您的显卡型号 $gpu_model 获取算力时出错，请联系技术支持。"
    exit 1
fi
echo "GPU1 Model: $gpu_model"
echo "Compute Capability: $compute_capability"

# 检查bc是否安装 bc是一个任意精度的计算器语言，用于计算数学表达式。 
# command -v bc 命令来检查 bc 是否存在于系统的命令路径中。
# &> /dev/null 将标准输出和标准错误重定向到/dev/null，即丢弃任何输出，只关注命令的返回值。
if ! command -v bc &> /dev/null; then # 如果 bc 命令不存在（command -v bc 返回非零值）
    echo "Error: bc 命令不存在，请使用 sudo apt update && sudo apt-get install bc 安装，再重新启动。"
    exit 1
fi

# 用bc来比较版本号大小
if [ $(echo "$compute_capability >= 7.5" | bc) -eq 1 ]; then
    OCR_USE_GPU="True"
    echo "OCR_USE_GPU=$OCR_USE_GPU because $compute_capability >= 7.5"
else
    OCR_USE_GPU="False"
    echo "OCR_USE_GPU=$OCR_USE_GPU because $compute_capability < 7.5"
fi
update_or_append_to_env "OCR_USE_GPU" "$OCR_USE_GPU"

# 使用nvidia-smi命令获取GPU的显存大小（以MiB为单位）
GPU1_MEMORY_SIZE=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits -i $gpu_id1)

OFFCUT_TOKEN=0
echo "===================================================="
echo "******************** 重要提示 ********************"
echo "===================================================="
echo ""

model_size=${MODEL_SIZE} # run.sh中设置的模型b数
model_size_num=$(echo $model_size | grep -oP '^[0-9]+(\.[0-9]+)?')

# 使用默认后端且model_size_num不为0
if [ "$runtime_backend" = "default" ] && [ "$model_size_num" -ne 0 ]; then
    if [ -z "$gpu_series" ]; then  # -z 检查 gpu_series是不是为空 即不是Nvidia 30系列或40系列 gpu_series前面已经获取
        echo "默认后端为FasterTransformer，仅支持Nvidia RTX 30系列或40系列显卡，您的显卡型号为： $gpu_model, 不在支持列表中，将自动为您切换后端："
        # 如果显存大于等于24GB且计算力大于等于8.6，则可以使用vllm后端
        if [ "$GPU1_MEMORY_SIZE" -ge 24000 ] && [ $(echo "$compute_capability >= 8.6" | bc) -eq 1 ]; then
            echo "根据匹配算法，已自动为您切换为vllm后端（推荐）"
            runtime_backend="vllm"
        else
            # 自动切换huggingface后端
            echo "根据匹配算法，已自动为您切换为huggingface后端"
            runtime_backend="hf"
        fi
    fi
fi

# 模型选择
if [ "$GPU1_MEMORY_SIZE" -lt 4000 ]; then # 显存小于4GB
    echo "您当前的显存为 $GPU1_MEMORY_SIZE MiB 不足以部署本项目，建议升级到GTX 1050Ti或以上级别的显卡"
    exit 1
elif [ "$model_size_num" -eq 0 ]; then  # 模型大小为0B, 表示使用openai api，4G显存就够了
    echo "您当前的显存为 $GPU1_MEMORY_SIZE MiB 可以使用在线的OpenAI API"
elif [ "$GPU1_MEMORY_SIZE" -lt 8000 ]; then  # 显存小于8GB
    # 显存小于8GB，仅推荐使用在线的OpenAI API
    echo "您当前的显存为 $GPU1_MEMORY_SIZE MiB 仅推荐使用在线的OpenAI API"
    if [ "$model_size_num" -gt 0 ]; then  # 模型大小大于0B
        echo "您的显存不足以部署 $model_size 模型，请重新选择模型大小"
        exit 1
    fi
elif [ "$GPU1_MEMORY_SIZE" -ge 8000 ] && [ "$GPU1_MEMORY_SIZE" -le 10000 ]; then  # 显存[8GB-10GB)
    # 8GB显存，推荐部署1.8B的大模型
    echo "您当前的显存为 $GPU1_MEMORY_SIZE MiB 推荐部署1.8B的大模型，包括在线的OpenAI API"
    if [ "$model_size_num" -gt 2 ]; then  # 模型大小大于2B
        echo "您的显存不足以部署 $model_size 模型，请重新选择模型大小"
        exit 1
    fi
elif [ "$GPU1_MEMORY_SIZE" -ge 10000 ] && [ "$GPU1_MEMORY_SIZE" -le 16000 ]; then  # 显存[10GB-16GB)
    # 10GB, 11GB, 12GB显存，推荐部署3B及3B以下的模型
    echo "您当前的显存为 $GPU1_MEMORY_SIZE MiB，推荐部署3B及3B以下的模型，包括在线的OpenAI API"
    if [ "$model_size_num" -gt 3 ]; then  # 模型大小大于3B
        echo "您的显存不足以部署 $model_size 模型，请重新选择模型大小"
        exit 1
    fi
elif [ "$GPU1_MEMORY_SIZE" -ge 16000 ] && [ "$GPU1_MEMORY_SIZE" -le 22000 ]; then  # 显存[16-22GB)
    # 16GB显存
    echo "您当前的显存为 $GPU1_MEMORY_SIZE MiB 推荐部署小于等于7B的大模型"
    if [ "$model_size_num" -gt 7 ]; then  # 模型大小大于7B
        echo "您的显存不足以部署 $model_size 模型，请重新选择模型大小"
        exit 1
    fi
    if [ "$runtime_backend" = "default" ]; then  # 默认使用Qwen-7B-QAnything+FasterTransformer
        if [ -n "$gpu_series" ]; then
            # Nvidia 30系列或40系列
            if [ $gpu_id1 -eq $gpu_id2 ]; then
                echo "为了防止显存溢出，tokens上限默认设置为2700"
                OFFCUT_TOKEN=1400
            else
                echo "tokens上限默认设置为4096"
                OFFCUT_TOKEN=0
            fi
        else
            echo "您的显卡型号 $gpu_model 不支持部署Qwen-7B-QAnything模型"
            exit 1
        fi
    elif [ "$runtime_backend" = "hf" ]; then  # 使用Huggingface Transformers后端
        if [ "$model_size_num" -le 7 ] && [ "$model_size_num" -gt 3 ]; then  # 模型大小大于3B，小于等于7B
            if [ $gpu_id1 -eq $gpu_id2 ]; then
                echo "为了防止显存溢出，tokens上限默认设置为1400"
                OFFCUT_TOKEN=2700
            else
                echo "为了防止显存溢出，tokens上限默认设置为2300"
                OFFCUT_TOKEN=1800
            fi
        else
            echo "tokens上限默认设置为4096"
            OFFCUT_TOKEN=0
        fi
    elif [ "$runtime_backend" = "vllm" ]; then  # 使用VLLM后端
        if [ "$model_size_num" -gt 3 ]; then  # 模型大小大于3B
            echo "您的显存不足以使用vllm后端部署 $model_size 模型"
            exit 1
        else
            echo "tokens上限默认设置为4096"
            OFFCUT_TOKEN=0
        fi
    fi
elif [ "$GPU1_MEMORY_SIZE" -ge 22000 ] && [ "$GPU1_MEMORY_SIZE" -le 25000 ]; then  # [22GB, 24GB]
    echo "您当前的显存为 $GPU1_MEMORY_SIZE MiB 推荐部署7B模型"
    if [ "$model_size_num" -gt 7 ]; then  # 模型大小大于7B
        echo "您的显存不足以部署 $model_size 模型，请重新选择模型大小"
        exit 1
    fi
    OFFCUT_TOKEN=0
elif [ "$GPU1_MEMORY_SIZE" -gt 25000 ]; then  # 显存大于24GB
    OFFCUT_TOKEN=0
fi
# 到GPU1_MEMORY_SIZE似乎只考虑了单张显卡，双显卡启动也只是用第一张显卡来运行，另一张显卡放embeddding模型

update_or_append_to_env "OFFCUT_TOKEN" "$OFFCUT_TOKEN"



start_time=$(date +%s)  # 记录开始时间

# 注意30系和40系的显卡会自动切换到hf或vllm后端，上面变的
if [ "$runtime_backend" = "default" ]; then
    echo "Executing default FastTransformer runtime_backend"
    # start llm server
    # 判断一下，如果gpu_id1和gpu_id2相同，则只启动一个triton_server 推理服务器
    if [ $gpu_id1 -eq $gpu_id2 ]; then
        echo "The triton server will start on $gpu_id1 GPU"
        # 设置CUDA_VISIBLE_DEVICES，并在后台不挂断的启动tritonserver
        CUDA_VISIBLE_DEVICES=$gpu_id1 nohup /opt/tritonserver/bin/tritonserver --model-store=/model_repos/QAEnsemble --http-port=10000 --grpc-port=10001 --metrics-port=10002 --log-verbose=1 >  /workspace/qanything_local/logs/debug_logs/llm_embed_rerank_tritonserver.log 2>&1 &
        update_or_append_to_env "RERANK_PORT" "10001"
        update_or_append_to_env "EMBED_PORT" "10001"
    else
        echo "The triton server will start on $gpu_id1 and $gpu_id2 GPUs"
        # 双GPU启动
        CUDA_VISIBLE_DEVICES=$gpu_id1 nohup /opt/tritonserver/bin/tritonserver --model-store=/model_repos/QAEnsemble_base --http-port=10000 --grpc-port=10001 --metrics-port=10002 --log-verbose=1 > /workspace/qanything_local/logs/debug_logs/llm_tritonserver.log 2>&1 &
        CUDA_VISIBLE_DEVICES=$gpu_id2 nohup /opt/tritonserver/bin/tritonserver --model-store=/model_repos/QAEnsemble_embed_rerank --http-port=9000 --grpc-port=9001 --metrics-port=9002 --log-verbose=1 > /workspace/qanything_local/logs/debug_logs/embed_rerank_tritonserver.log 2>&1 &
        update_or_append_to_env "RERANK_PORT" "9001"
        update_or_append_to_env "EMBED_PORT" "9001"
    fi
    # 运行切换到 LLM 服务器目录并启动 Python 脚本
    cd /workspace/qanything_local/qanything_kernel/dependent_server/llm_for_local_serve || exit
    nohup python3 -u llm_server_entrypoint.py --host="0.0.0.0" --port=36001 --model-path="tokenizer_assets" --model-url="0.0.0.0:10001" > /workspace/qanything_local/logs/debug_logs/llm_server_entrypoint.log 2>&1 &
    echo "The llm transfer service is ready! (1/8)"
    echo "大模型中转服务已就绪! (1/8)"
else
    # 启动嵌入和重排名的 Triton 服务器，使用 gpu_id2
    echo "The triton server for embedding and reranker will start on $gpu_id2 GPUs"
    CUDA_VISIBLE_DEVICES=$gpu_id2 nohup /opt/tritonserver/bin/tritonserver --model-store=/model_repos/QAEnsemble_embed_rerank --http-port=9000 --grpc-port=9001 --metrics-port=9002 --log-verbose=1 > /workspace/qanything_local/logs/debug_logs/embed_rerank_tritonserver.log 2>&1 &
    update_or_append_to_env "RERANK_PORT" "9001"
    update_or_append_to_env "EMBED_PORT" "9001"
    # 处理模型和环境变量的配置
    LLM_API_SERVE_CONV_TEMPLATE="$conv_template"
    LLM_API_SERVE_MODEL="$model_name"

    check_folder_existence "$LLM_API_SERVE_MODEL"

    update_or_append_to_env "LLM_API_SERVE_PORT" "7802"
    update_or_append_to_env "LLM_API_SERVE_MODEL" "$LLM_API_SERVE_MODEL"
    update_or_append_to_env "LLM_API_SERVE_CONV_TEMPLATE" "$LLM_API_SERVE_CONV_TEMPLATE"
    # 启动 FastChat 相关的服务
    mkdir -p /workspace/qanything_local/logs/debug_logs/fastchat_logs && cd /workspace/qanything_local/logs/debug_logs/fastchat_logs
    nohup python3 -m fastchat.serve.controller --host 0.0.0.0 --port 7800 > /workspace/qanything_local/logs/debug_logs/fastchat_logs/fschat_controller_7800.log 2>&1 &
    nohup python3 -m fastchat.serve.openai_api_server --host 0.0.0.0 --port 7802 --controller-address http://0.0.0.0:7800 > /workspace/qanything_local/logs/debug_logs/fastchat_logs/fschat_openai_api_server_7802.log 2>&1 &

    gpus=$tensor_parallel
    if [ $tensor_parallel -eq 2 ]; then
        gpus="$gpu_id1,$gpu_id2"
    else
        gpus="$gpu_id1"
    fi

    # 在hf和vllm后端中选择
    case $runtime_backend in
    "hf")
        echo "Executing hf runtime_backend"
        
        CUDA_VISIBLE_DEVICES=$gpus nohup python3 -m fastchat.serve.model_worker --host 0.0.0.0 --port 7801 \
            --controller-address http://0.0.0.0:7800 --worker-address http://0.0.0.0:7801 \
            --model-path /model_repos/CustomLLM/$LLM_API_SERVE_MODEL --load-8bit \
            --gpus $gpus --num-gpus $tensor_parallel --dtype bfloat16 --conv-template $LLM_API_SERVE_CONV_TEMPLATE > /workspace/qanything_local/logs/debug_logs/fastchat_logs/fschat_model_worker_7801.log 2>&1 &

        ;;
    "vllm")
        echo "Executing vllm runtime_backend"

        CUDA_VISIBLE_DEVICES=$gpus nohup python3 -m fastchat.serve.vllm_worker --host 0.0.0.0 --port 7801 \
            --controller-address http://0.0.0.0:7800 --worker-address http://0.0.0.0:7801 \
            --model-path /model_repos/CustomLLM/$LLM_API_SERVE_MODEL --trust-remote-code --block-size 32 --tensor-parallel-size $tensor_parallel \
            --max-model-len 4096 --gpu-memory-utilization $gpu_memory_utilization --dtype bfloat16 --conv-template $LLM_API_SERVE_CONV_TEMPLATE > /workspace/qanything_local/logs/debug_logs/fastchat_logs/fschat_model_worker_7801.log 2>&1 &
        
        ;;
    "sglang")
        echo "Executing sglang runtime_backend"
        ;;
    *)
        echo "Invalid runtime_backend option"; exit 1
        ;;
    esac
fi

# 后台启动 rerank_server.py
cd /workspace/qanything_local || exit
nohup python3 -u qanything_kernel/dependent_server/rerank_for_local_serve/rerank_server.py > /workspace/qanything_local/logs/debug_logs/rerank_server.log 2>&1 &
echo "The rerank service is ready! (2/8)"
echo "rerank服务已就绪! (2/8)"

# 在gpu2上启动 ocr_server.py (如果只有一张显卡，gpu2和gpu2一样)
CUDA_VISIBLE_DEVICES=$gpu_id2 nohup python3 -u qanything_kernel/dependent_server/ocr_serve/ocr_server.py > /workspace/qanything_local/logs/debug_logs/ocr_server.log 2>&1 &
echo "The ocr service is ready! (3/8)"
echo "OCR服务已就绪! (3/8)"

# 后台启动sanic_api.py（这是总后端服务）
nohup python3 -u qanything_kernel/qanything_server/sanic_api.py --mode "local" > /workspace/qanything_local/logs/debug_logs/sanic_api.log 2>&1 &

# 监听后端服务启动 记录当前sanic后端启动的时间戳
backend_start_time=$(date +%s)

# 进入循环，反复grep（查找） sanic_api.log 检查日志文件是否包含 "Starting worker" 字样
while ! grep -q "Starting worker" /workspace/qanything_local/logs/debug_logs/sanic_api.log; do
    echo "Waiting for the backend service to start..."
    echo "等待启动后端服务"
    sleep 1

    # 获取当前时间并计算经过的时间
    current_time=$(date +%s)
    elapsed_time=$((current_time - backend_start_time))

    # 检查是否超时
    if [ $elapsed_time -ge 120 ]; then
        echo "启动后端服务超时，请检查日志文件 /workspace/qanything_local/logs/debug_logs/sanic_api.log 获取更多信息。"
        exit 1
    fi
    sleep 5
done

# 如果成功则会输出 
echo "The qanything backend service is ready! (4/8)"
echo "qanything后端服务已就绪! (4/8)"


# 确定log日志的路径
# 这个地方暂时不清楚到底是为什么要这么分
if [ "$runtime_backend" = "default" ]; then
    if [ $gpu_id1 -eq $gpu_id2 ]; then
        llm_log_file="/workspace/qanything_local/logs/debug_logs/llm_embed_rerank_tritonserver.log"
        embed_rerank_log_file=" /workspace/qanything_local/logs/debug_logs/llm_embed_rerank_tritonserver.log"
    else
        llm_log_file="/workspace/qanything_local/logs/debug_logs/llm_tritonserver.log"
        embed_rerank_log_file="/workspace/qanything_local/logs/debug_logs/embed_rerank_tritonserver.log"
    fi
else
    llm_log_file="/workspace/qanything_local/logs/debug_logs/fastchat_logs/fschat_model_worker_7801.log"
    embed_rerank_log_file="/workspace/qanything_local/logs/debug_logs/embed_rerank_tritonserver.log"
fi

# embedding服务 启动和健康状态检查
# tail -f 命令用于实时监控日志文件 $embed_rerank_log_file 的内容
tail -f $embed_rerank_log_file &  # 后台输出日志文件
tail_pid=$!  # 获取tail命令的进程ID，以便后续关闭

# 记录Embedding 和 Rerank启动时间
now_time=$(date +%s)
while true; do # 进入一个无限循环，定期检查服务的健康状态和是否超时
    current_time=$(date +%s)
    elapsed_time=$((current_time - now_time))

    # 检查指定服务的健康状态
    # 使用 curl 命令请求对应的健康检查端点，并获取 HTTP 响应状态码
    if [ "$runtime_backend" = "default" ]; then
        if [ $gpu_id1 -eq $gpu_id2 ]; then
            embed_rerank_response=$(curl -s -w "%{http_code}" http://localhost:10000/v2/health/ready -o /dev/null)
        else
            embed_rerank_response=$(curl -s -w "%{http_code}" http://localhost:9000/v2/health/ready -o /dev/null)
        fi
    else
        embed_rerank_response=$(curl -s -w "%{http_code}" http://localhost:9000/v2/health/ready -o /dev/null)
    fi

    # 检查是否超时
    # 如果服务启动超时（120秒），关闭 tail 命令，并检查日志文件中是否有错误信息
    if [ $elapsed_time -ge 120 ]; then
        kill $tail_pid  # 关闭后台的tail命令
        echo "启动 embedding and rerank 服务超时，自动检查 $embed_rerank_log_file 中是否存在Error..."

        check_log_errors "$embed_rerank_log_file" # 检查日志中的错误信息

        exit 1
    fi

    # 如果健康检查返回状态码 200，说明服务启动成功，关闭 tail 命令并输出成功信息
    if [ $embed_rerank_response -eq 200 ]; then
        kill $tail_pid  # 关闭后台的tail命令
        echo "The embedding and rerank service is ready!. (7.5/8)"
        echo "Embedding 和 Rerank 服务已准备就绪！(7.5/8)"
        break
    fi

    echo "The embedding and rerank service is starting up, it can be long... you have time to make a coffee :)"
    echo "Embedding and Rerank 服务正在启动，可能需要一段时间...你有时间去冲杯咖啡 :)"
    sleep 10
done

# LLM服务 启动和健康状态检查
tail -f $llm_log_file &  # 后台输出日志文件
tail_pid=$!  # 获取tail命令的进程ID，以便后续关闭

now_time=$(date +%s)
while true; do
    current_time=$(date +%s)
    elapsed_time=$((current_time - now_time))

    # 检查是否超时 如果 LLM 服务启动超时（300秒），关闭 tail 命令并检查日志文件中的错误
    if [ $elapsed_time -ge 300 ]; then
        kill $tail_pid  # 关闭后台的tail命令
        echo "启动 LLM 服务超时，自动检查 $llm_log_file 中是否存在Error..."

        check_log_errors "$llm_log_file"

        exit 1
    fi


    if [ "$runtime_backend" = "default" ]; then
        llm_response=$(curl -s -w "%{http_code}" http://localhost:10000/v2/health/ready -o /dev/null)
    else # 对于非默认后端，使用 POST 请求获取模型列表
        llm_response=$(curl --request POST --url http://localhost:7800/list_models)
    fi

    # 检查返回状态码或模型名称，确定服务是否成功启动
    if [ "$runtime_backend" = "default" ]; then
        if [ $llm_response -eq 200 ]; then
            kill $tail_pid  # 关闭后台的tail命令
            echo "The llm service is ready!, now you can use the qanything service. (8/8)"
            echo "LLM 服务已准备就绪！现在您可以使用qanything服务。（8/8)"
            break
        fi
    else
        if [[ $llm_response == *"$LLM_API_SERVE_MODEL"* ]]; then
            kill $tail_pid  # 关闭后台的tail命令
            echo "The llm service is ready!, now you can use the qanything service. (8/8)"
            echo "LLM 服务已准备就绪！现在您可以使用qanything服务。（8/8)"
            break
        fi
    fi

    echo "The llm service is starting up, it can be long... you have time to make a coffee :)"
    echo "LLM 服务正在启动，可能需要一段时间...你有时间去冲杯咖啡 :)"
    sleep 10
done

echo "开始检查日志文件中的错误信息..."
# 调用函数并传入日志文件路径
check_log_errors "/workspace/qanything_local/logs/debug_logs/rerank_server.log"
check_log_errors "/workspace/qanything_local/logs/debug_logs/ocr_server.log"
check_log_errors "/workspace/qanything_local/logs/debug_logs/sanic_api.log"

current_time=$(date +%s)
elapsed=$((current_time - start_time))  # 计算经过的时间（秒）
echo "Time elapsed: ${elapsed} seconds."
echo "已耗时: ${elapsed} 秒."
user_ip=$USER_IP
echo "Please visit the front-end service at [http://$user_ip:8777/qanything/] to conduct Q&A."
echo "请在[http://$user_ip:8777/qanything/]下访问前端服务来进行问答，如果前端报错，请在浏览器按F12以获取更多报错信息"

# 保持容器运行
while true; do
  sleep 2
done


