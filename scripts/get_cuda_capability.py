import pycuda.driver as cuda
import pycuda.autoinit
import sys  # 导入sys模块来读取命令行参数

def get_cuda_device_major_minor(device_id=0):
    cuda.init() # 初始化 CUDA 环境
    device = cuda.Device(device_id) # 根据传入的设备ID获取对应的CUDA设备对象
    attributes = device.get_attributes()  # 获取设备的属性字典
    # 从属性字典中提取计算能力的主版本号和次版本号
    major = attributes[cuda.device_attribute.COMPUTE_CAPABILITY_MAJOR]
    minor = attributes[cuda.device_attribute.COMPUTE_CAPABILITY_MINOR]
    cmp_ver = f"{major}.{minor}" # 将主版本号和次版本号拼接成字符串并返回
    return cmp_ver

# 从命令行参数获取设备号
device_id = 0  # 默认设备号
if len(sys.argv) > 1:
    device_id = int(sys.argv[1])  # 将传入的参数转换为整数

cmp_ver = get_cuda_device_major_minor(device_id)
print(cmp_ver)  # 打印结果以便在Shell中捕获