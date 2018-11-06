extern "C" {
#include <ccv.h>
#include <ccv_internal.h>
#include <nnc/ccv_nnc.h>
#include <nnc/ccv_nnc_easy.h>
#include <nnc/ccv_nnc_internal.h>
}
#include <nnc/gpu/ccv_nnc_compat.h>

#ifdef HAVE_CUDNN

static int _ccv_nnc_ewsum_forw(const ccv_nnc_cmd_t cmd, const ccv_nnc_hint_t hint, const int flags, ccv_nnc_tensor_t* const* const inputs, const int input_size, ccv_nnc_tensor_t* const* const outputs, const int output_size, ccv_nnc_stream_context_t* const stream_context)
{
	assert(output_size >= 1);
	cudnnHandle_t cudnn = ccv_nnc_stream_context_get_cudnn(stream_context);
	int z;
	static const float one = 1;
	int k = 0;
	// Bad, I promised this can be inplace operation. Need to first find out if there are share the same pointer first.
	for (z = 1; z < input_size; z++)
		if (outputs[0]->data.f32 == inputs[z]->data.f32)
		{
			k = z;
			break;
		}
	const ccv_nnc_cudnn_tensor_view_descriptor_t c = ccv_nnc_cudnn_get_tensor_view_descriptor_for_op(stream_context, (const ccv_nnc_tensor_view_t*)outputs[0]);
	for (z = 0; z < input_size - 1; z++)
	{
		const ccv_nnc_cudnn_tensor_view_descriptor_t a = z > 0 ? c : ccv_nnc_cudnn_get_tensor_view_descriptor_for_op(stream_context, (const ccv_nnc_tensor_view_t*)inputs[k]);
		const ccv_nnc_cudnn_tensor_view_descriptor_t b = ccv_nnc_cudnn_get_tensor_view_descriptor_for_op(stream_context, (const ccv_nnc_tensor_view_t*)(z >= k ? inputs[z + 1] : inputs[z]));
		static const float zero = 0;
		cudnnOpTensorDescriptor_t add = ccv_nnc_stream_context_get_op_tensor_descriptor(stream_context);
		cudnnSetOpTensorDescriptor(add, CUDNN_OP_TENSOR_ADD, CUDNN_DATA_FLOAT, CUDNN_PROPAGATE_NAN);
		CUDNN_ENFORCE(cudnnOpTensor(cudnn, add, &one, a.descriptor, a.data.u8, &one, b.descriptor, b.data.u8, &zero, c.descriptor, c.data.u8));
		ccv_nnc_stream_context_return_op_tensor_descriptor(stream_context, add);
		if (z == 0)
			ccv_nnc_cudnn_deinit_tensor_view_descriptor(a);
		ccv_nnc_cudnn_deinit_tensor_view_descriptor(b);
	}
	ccv_nnc_cudnn_deinit_tensor_view_descriptor(c);
	return CCV_NNC_EXEC_SUCCESS;
}

static int _ccv_nnc_ewsum_back(const ccv_nnc_cmd_t cmd, const ccv_nnc_hint_t hint, const int flags, ccv_nnc_tensor_t* const* const inputs, const int input_size, ccv_nnc_tensor_t* const* const outputs, const int output_size, ccv_nnc_stream_context_t* const stream_context)
{
	cudnnHandle_t cudnn = ccv_nnc_stream_context_get_cudnn(stream_context);
	static const float one = 1;
	int i;
	if (input_size <= 0 || inputs[0] == 0)
	{
		for (i = 0; i < output_size; i++)
			if (outputs[i])
			{
				const ccv_nnc_cudnn_tensor_view_descriptor_t a = ccv_nnc_cudnn_get_tensor_view_descriptor_for_op(stream_context, (const ccv_nnc_tensor_view_t*)outputs[i]);
				CUDNN_ENFORCE(cudnnSetTensor(cudnn, a.descriptor, a.data.u8, &one));
				ccv_nnc_cudnn_deinit_tensor_view_descriptor(a);
			}
	} else {
		static const float zero = 0;
		const ccv_nnc_cudnn_tensor_view_descriptor_t g = ccv_nnc_cudnn_get_tensor_view_descriptor_for_op(stream_context, (const ccv_nnc_tensor_view_t*)inputs[0]);
		for (i = 0; i < output_size; i++)
			if (outputs[i] && inputs[0]->data.f32 != outputs[i]->data.f32)
			{
				ccv_nnc_cudnn_tensor_view_descriptor_t a = ccv_nnc_cudnn_get_tensor_view_descriptor_for_op(stream_context, (const ccv_nnc_tensor_view_t*)outputs[i]);
				CUDNN_ENFORCE(cudnnTransformTensor(cudnn, &one, g.descriptor, g.data.u8,  &zero, a.descriptor, a.data.u8));
				ccv_nnc_cudnn_deinit_tensor_view_descriptor(a);
			}
		ccv_nnc_cudnn_deinit_tensor_view_descriptor(g);
	}
	return CCV_NNC_EXEC_SUCCESS;
}

#endif

REGISTER_COMMAND_BACKEND(CCV_NNC_EWSUM_FORWARD, CCV_NNC_BACKEND_GPU_CUDNN)(ccv_nnc_cmd_backend_registry_t* const registry)
{
#ifdef HAVE_CUDNN
	registry->tensor_formats = CCV_TENSOR_FORMAT_NHWC | CCV_TENSOR_FORMAT_NCHW | CCV_TENSOR_FORMAT_CHWN;
	registry->tensor_datatypes = CCV_32F;
	registry->tensor_memory = CCV_TENSOR_GPU_MEMORY;
	registry->algorithms = 1;
	registry->exec = _ccv_nnc_ewsum_forw;
#endif
}

REGISTER_COMMAND_BACKEND(CCV_NNC_EWSUM_BACKWARD, CCV_NNC_BACKEND_GPU_CUDNN)(ccv_nnc_cmd_backend_registry_t* const registry)
{
#ifdef HAVE_CUDNN
	registry->tensor_formats = CCV_TENSOR_FORMAT_NHWC | CCV_TENSOR_FORMAT_NCHW | CCV_TENSOR_FORMAT_CHWN;
	registry->tensor_datatypes = CCV_32F;
	registry->tensor_memory = CCV_TENSOR_GPU_MEMORY;
	registry->algorithms = 1;
	registry->exec = _ccv_nnc_ewsum_back;
#endif
}

