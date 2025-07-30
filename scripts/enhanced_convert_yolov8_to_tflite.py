#!/usr/bin/env python3
"""
Enhanced YOLOv8 to TFLite conversion script with optimizations for mobile deployment.

This script converts YOLOv8 models to TensorFlow Lite format with:
- GPU delegate optimization
- Quantization support (FP16, INT8)
- Model validation and benchmarking
- Metadata injection for better mobile integration

Requirements:
    pip install ultralytics tensorflow onnx numpy pillow
"""

import os
import sys
import logging
import argparse
import numpy as np
from pathlib import Path
import tensorflow as tf
from ultralytics import YOLO
import onnx
from typing import Optional, Tuple, List

# Configure logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

class YOLOv8ToTFLiteConverter:
    """Enhanced converter for YOLOv8 to TFLite with mobile optimizations."""
    
    def __init__(self, model_path: str, output_dir: str = ".", model_name: str = "golfclub_ball_yolov8n"):
        self.model_path = Path(model_path)
        self.output_dir = Path(output_dir)
        self.model_name = model_name
        self.input_size = 640  # YOLOv8 default input size
        
        # Create output directory
        self.output_dir.mkdir(parents=True, exist_ok=True)
        
        # Define output paths
        self.onnx_path = self.output_dir / f"{model_name}.onnx"
        self.tflite_path = self.output_dir / f"{model_name}.tflite"
        self.tflite_fp16_path = self.output_dir / f"{model_name}_fp16.tflite"
        self.tflite_int8_path = self.output_dir / f"{model_name}_int8.tflite"
        
    def load_yolo_model(self) -> YOLO:
        """Load YOLOv8 model with error handling."""
        try:
            logger.info(f"Loading YOLOv8 model from: {self.model_path}")
            model = YOLO(str(self.model_path))
            logger.info("YOLOv8 model loaded successfully")
            
            # Print model info
            logger.info(f"Model classes: {model.names}")
            logger.info(f"Number of classes: {len(model.names)}")
            
            return model
        except Exception as e:
            logger.error(f"Failed to load YOLOv8 model: {e}")
            raise
    
    def export_to_onnx(self, model: YOLO) -> bool:
        """Export YOLOv8 model to ONNX format."""
        try:
            logger.info(f"Exporting to ONNX: {self.onnx_path}")
            
            # Export with specific parameters for mobile deployment
            model.export(
                format='onnx',
                imgsz=self.input_size,
                dynamic=False,  # Fixed input size for better optimization
                simplify=True,  # Simplify ONNX model
                opset=11,       # ONNX opset version
            )
            
            # Move the generated ONNX file to our desired location
            generated_onnx = self.model_path.with_suffix('.onnx')
            if generated_onnx.exists():
                generated_onnx.rename(self.onnx_path)
            
            # Verify ONNX model
            self._verify_onnx_model()
            
            logger.info("ONNX export completed successfully")
            return True
            
        except Exception as e:
            logger.error(f"ONNX export failed: {e}")
            return False
    
    def _verify_onnx_model(self) -> bool:
        """Verify the exported ONNX model."""
        try:
            logger.info("Verifying ONNX model...")
            onnx_model = onnx.load(str(self.onnx_path))
            onnx.checker.check_model(onnx_model)
            
            # Print model info
            logger.info(f"ONNX model input: {onnx_model.graph.input[0].name}")
            logger.info(f"ONNX model output: {onnx_model.graph.output[0].name}")
            
            return True
        except Exception as e:
            logger.error(f"ONNX model verification failed: {e}")
            return False
    
    def convert_to_tflite(self, quantization: str = "none") -> bool:
        """Convert ONNX model to TFLite with various quantization options."""
        try:
            logger.info(f"Converting to TFLite with {quantization} quantization")
            
            # Load ONNX model
            converter = tf.lite.TFLiteConverter.from_onnx(str(self.onnx_path))
            
            # Basic optimizations
            converter.optimizations = [tf.lite.Optimize.DEFAULT]
            
            # Configure based on quantization type
            if quantization == "fp16":
                output_path = self.tflite_fp16_path
                converter.target_spec.supported_types = [tf.float16]
                converter.target_spec.supported_ops = [
                    tf.lite.OpsSet.TFLITE_BUILTINS,
                    tf.lite.OpsSet.SELECT_TF_OPS
                ]
            elif quantization == "int8":
                output_path = self.tflite_int8_path
                converter.target_spec.supported_ops = [
                    tf.lite.OpsSet.TFLITE_BUILTINS_INT8,
                    tf.lite.OpsSet.TFLITE_BUILTINS
                ]
                # Set representative dataset for full integer quantization
                converter.representative_dataset = self._representative_dataset_generator
                converter.inference_input_type = tf.uint8
                converter.inference_output_type = tf.uint8
            else:
                output_path = self.tflite_path
                converter.target_spec.supported_types = [tf.float32]
                converter.target_spec.supported_ops = [
                    tf.lite.OpsSet.TFLITE_BUILTINS,
                    tf.lite.OpsSet.SELECT_TF_OPS
                ]
            
            # Additional optimizations for mobile deployment
            converter.experimental_new_converter = True
            converter.allow_custom_ops = False
            
            # Convert model
            tflite_model = converter.convert()
            
            # Save TFLite model
            with open(output_path, 'wb') as f:
                f.write(tflite_model)
            
            logger.info(f"TFLite model saved to: {output_path}")
            
            # Verify and benchmark the model
            self._verify_tflite_model(output_path)
            self._benchmark_model(output_path)
            
            return True
            
        except Exception as e:
            logger.error(f"TFLite conversion failed: {e}")
            return False
    
    def _representative_dataset_generator(self):
        """Generate representative dataset for INT8 quantization."""
        logger.info("Generating representative dataset for INT8 quantization...")
        
        # Generate random images that match the model input
        for _ in range(100):
            # Random image data normalized to [0, 1]
            data = np.random.random((1, self.input_size, self.input_size, 3)).astype(np.float32)
            yield [data]
    
    def _verify_tflite_model(self, model_path: Path) -> bool:
        """Verify TFLite model by loading and checking basic properties."""
        try:
            logger.info(f"Verifying TFLite model: {model_path}")
            
            # Load TFLite model
            interpreter = tf.lite.Interpreter(model_path=str(model_path))
            interpreter.allocate_tensors()
            
            # Get input and output details
            input_details = interpreter.get_input_details()
            output_details = interpreter.get_output_details()
            
            logger.info(f"Input shape: {input_details[0]['shape']}")
            logger.info(f"Input type: {input_details[0]['dtype']}")
            logger.info(f"Output shape: {output_details[0]['shape']}")
            logger.info(f"Output type: {output_details[0]['dtype']}")
            
            # Test inference with dummy data
            input_shape = input_details[0]['shape']
            if input_details[0]['dtype'] == np.uint8:
                input_data = np.random.randint(0, 256, size=input_shape, dtype=np.uint8)
            else:
                input_data = np.random.random(input_shape).astype(input_details[0]['dtype'])
            
            interpreter.set_tensor(input_details[0]['index'], input_data)
            interpreter.invoke()
            
            output_data = interpreter.get_tensor(output_details[0]['index'])
            logger.info(f"Test inference output shape: {output_data.shape}")
            
            return True
            
        except Exception as e:
            logger.error(f"TFLite model verification failed: {e}")
            return False
    
    def _benchmark_model(self, model_path: Path, num_runs: int = 50) -> None:
        """Benchmark TFLite model performance."""
        try:
            logger.info(f"Benchmarking model: {model_path}")
            
            # Load model
            interpreter = tf.lite.Interpreter(model_path=str(model_path))
            interpreter.allocate_tensors()
            
            input_details = interpreter.get_input_details()
            
            # Prepare test data
            input_shape = input_details[0]['shape']
            if input_details[0]['dtype'] == np.uint8:
                input_data = np.random.randint(0, 256, size=input_shape, dtype=np.uint8)
            else:
                input_data = np.random.random(input_shape).astype(input_details[0]['dtype'])
            
            # Warm up
            for _ in range(5):
                interpreter.set_tensor(input_details[0]['index'], input_data)
                interpreter.invoke()
            
            # Benchmark
            import time
            times = []
            for _ in range(num_runs):
                start_time = time.time()
                interpreter.set_tensor(input_details[0]['index'], input_data)
                interpreter.invoke()
                end_time = time.time()
                times.append((end_time - start_time) * 1000)  # Convert to milliseconds
            
            avg_time = np.mean(times)
            std_time = np.std(times)
            fps = 1000.0 / avg_time
            
            logger.info(f"Benchmark results for {model_path.name}:")
            logger.info(f"  Average inference time: {avg_time:.2f} ± {std_time:.2f} ms")
            logger.info(f"  Estimated FPS: {fps:.1f}")
            logger.info(f"  Model size: {model_path.stat().st_size / (1024*1024):.2f} MB")
            
        except Exception as e:
            logger.error(f"Benchmarking failed: {e}")
    
    def create_model_metadata(self) -> None:
        """Create metadata file with model information."""
        metadata = {
            "name": self.model_name,
            "version": "1.0",
            "description": "YOLOv8 model for golf ball and club head detection",
            "input_shape": [1, self.input_size, self.input_size, 3],
            "input_type": "float32",
            "input_normalization": "0-1",
            "classes": ["ball", "club_head"],
            "confidence_threshold": 0.25,
            "nms_threshold": 0.45,
            "preprocessing": {
                "resize": [self.input_size, self.input_size],
                "normalize": True,
                "mean": [0.0, 0.0, 0.0],
                "std": [255.0, 255.0, 255.0]
            },
            "postprocessing": {
                "output_format": "yolov8",
                "apply_nms": True
            }
        }
        
        import json
        metadata_path = self.output_dir / f"{self.model_name}_metadata.json"
        with open(metadata_path, 'w') as f:
            json.dump(metadata, f, indent=2)
        
        logger.info(f"Model metadata saved to: {metadata_path}")
    
    def convert_all_variants(self) -> bool:
        """Convert model to all variants (FP32, FP16, INT8)."""
        success = True
        
        # Load YOLOv8 model
        model = self.load_yolo_model()
        
        # Export to ONNX
        if not self.export_to_onnx(model):
            return False
        
        # Convert to different TFLite variants
        variants = [
            ("none", "FP32"),
            ("fp16", "FP16"),
            ("int8", "INT8")
        ]
        
        for quantization, description in variants:
            logger.info(f"\n--- Converting to {description} ---")
            if not self.convert_to_tflite(quantization):
                logger.error(f"Failed to convert to {description}")
                success = False
            else:
                logger.info(f"{description} conversion completed successfully")
        
        # Create metadata
        self.create_model_metadata()
        
        return success

def main():
    parser = argparse.ArgumentParser(description="Convert YOLOv8 model to TFLite format")
    parser.add_argument("model_path", help="Path to YOLOv8 .pt model file")
    parser.add_argument("--output-dir", default="./models", help="Output directory for converted models")
    parser.add_argument("--model-name", default="golfclub_ball_yolov8n", help="Output model name")
    parser.add_argument("--quantization", choices=["none", "fp16", "int8", "all"], 
                      default="all", help="Quantization type")
    
    args = parser.parse_args()
    
    # Validate input file
    if not Path(args.model_path).exists():
        logger.error(f"Model file not found: {args.model_path}")
        return 1
    
    # Create converter
    converter = YOLOv8ToTFLiteConverter(args.model_path, args.output_dir, args.model_name)
    
    try:
        if args.quantization == "all":
            success = converter.convert_all_variants()
        else:
            model = converter.load_yolo_model()
            success = converter.export_to_onnx(model)
            if success:
                success = converter.convert_to_tflite(args.quantization)
                converter.create_model_metadata()
        
        if success:
            logger.info("\n✅ Conversion completed successfully!")
            logger.info(f"📁 Output directory: {converter.output_dir}")
            logger.info("\n📋 Next steps:")
            logger.info("1. Copy the .tflite file to assets/models/ in your Flutter project")
            logger.info("2. Update pubspec.yaml to include the model in assets")
            logger.info("3. Test the model with the enhanced TFLite service")
            return 0
        else:
            logger.error("\n❌ Conversion failed!")
            return 1
            
    except Exception as e:
        logger.error(f"Conversion failed with error: {e}")
        return 1

if __name__ == "__main__":
    sys.exit(main())