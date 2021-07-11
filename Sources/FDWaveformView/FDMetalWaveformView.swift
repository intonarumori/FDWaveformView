//
//  File.swift
//  
//
//  Created by Daniel Langh on 2020. 11. 17..
//

import UIKit
import MetalKit

@available(iOS 9.0, *)
class FDMetalWaveformView: UIView {
    
    var mtkView: MTKView!
    var renderer: FDMetalRenderer!
    
    var pipelineState: MTLRenderPipelineState!
    
    // MARK: -
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }
    
    // MARK: -
    
    private func setup() {
        let mtkView = MTKView()
        mtkView.translatesAutoresizingMaskIntoConstraints = false
        self.mtkView = mtkView
        
        self.addSubview(mtkView)
        self.addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "|[mtkView]|", options: [], metrics: nil, views: ["mtkView" : mtkView]))
        self.addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "V:|[mtkView]|", options: [], metrics: nil, views: ["mtkView" : mtkView]))
        
        let device = MTLCreateSystemDefaultDevice()!
        mtkView.device = device
        mtkView.sampleCount = 4
        
        mtkView.colorPixelFormat = .bgra8Unorm_srgb
        mtkView.depthStencilPixelFormat = .depth32Float
        
        renderer = FDMetalRenderer(device: device,
                                   colorPixelFormat: mtkView.colorPixelFormat,
                                   depthStencilPixelFormat: mtkView.depthStencilPixelFormat,
                                   sampleCount: mtkView.sampleCount)

        mtkView.delegate = renderer
    }
    
    // MARK: -
}


@available(iOS 9.0, *)
class FDMetalRenderer: NSObject, MTKViewDelegate {
    
    let device: MTLDevice
    let commandQueue: MTLCommandQueue
    let depthStencilState: MTLDepthStencilState
    
    var viewMatrix = matrix_identity_float4x4

    var lastRenderTime: CFTimeInterval?

    init(device: MTLDevice,
         colorPixelFormat: MTLPixelFormat,
         depthStencilPixelFormat: MTLPixelFormat,
         sampleCount: Int) {
        
        self.device = device
        commandQueue = device.makeCommandQueue()!
        depthStencilState = FDMetalRenderer.buildDepthStencilState(device: device)
        //camera = Camera(position: float3(0, 0, 2))

        super.init()
    }
    
    static func buildDepthStencilState(device: MTLDevice) -> MTLDepthStencilState {
        let depthStencilDescriptor = MTLDepthStencilDescriptor()
        depthStencilDescriptor.depthCompareFunction = .less
        depthStencilDescriptor.isDepthWriteEnabled = true
        return device.makeDepthStencilState(descriptor: depthStencilDescriptor)!
    }

    // MARK: -

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
    }
    
    func draw(in view: MTKView) {
        
        //updateMatrices(view)
        
        if
            let commandBuffer = commandQueue.makeCommandBuffer(),
            let renderPassDescriptor = view.currentRenderPassDescriptor,
            let drawable = view.currentDrawable,
            let commandEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) {
            
            renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColorMake(0.63, 0.81, 1.0, 1.0)
            
            commandEncoder.setFrontFacing(.counterClockwise)
            commandEncoder.setCullMode(.back)
            commandEncoder.setDepthStencilState(depthStencilState)

//            delegate?.render(
//                renderer: self, commandEncoder: commandEncoder, commandBuffer: commandBuffer,
//                projectionMatrix: camera.projectionMatrix, viewMatrix: viewMatrix,
//                cameraPosition: camera.position)
            
            commandEncoder.endEncoding()
            commandBuffer.present(drawable)
            commandBuffer.commit()
        }
    }

}


// MARK: -

@available(iOS 9.0, *)
class Circle {
    
    let vertexBuffer: MTLBuffer
    let vertexCount: Int
    
    var transform: float4x4 = matrix_identity_float4x4

    // MARK: -
    
    init(device: MTLDevice, radius: Float, count: Int, color: SIMD3<Float>) {
        
        vertexCount = count
        
        let vertices = UnsafeMutableBufferPointer<ColoredVertex>.allocate(capacity: count)
        defer { vertices.deallocate() }

        for i in 0 ..< count {
            let angle = Double(i) / Double(count - 1) * Double.pi * 2
            vertices[i].position = float3(radius * Float(sin(angle)), 0, radius * Float(cos(angle)))
            vertices[i].color = color
        }
        let vertexBuffer = device.makeBuffer(bytes: vertices.baseAddress!,
                                             length: MemoryLayout<ColoredVertex>.stride * vertices.count,
                                             options: [.storageModeShared])!
        self.vertexBuffer = vertexBuffer
    }
    
    // MARK: -
    
    func update(deltaTime: CFTimeInterval) {}
    
    func render(commandEncoder: MTLRenderCommandEncoder, commandBuffer: MTLCommandBuffer,
                pipeline: MTLRenderPipelineState,
                projectionMatrix: float4x4, viewMatrix: float4x4, cameraPosition: SIMD3<Float>) {
        
        var mvpMatrix = projectionMatrix * viewMatrix * transform
        
        commandEncoder.setRenderPipelineState(pipeline)
        commandEncoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        commandEncoder.setVertexBytes(&mvpMatrix, length: MemoryLayout<float4x4>.stride, index: 1)
        commandEncoder.drawPrimitives(type: .lineStrip, vertexStart: 0, vertexCount: vertexCount)
    }
    
    // MARK: -
    
    static func createPipelineDescriptor(
        library: MTLLibrary,
        colorPixelFormat: MTLPixelFormat,
        depthStencilPixelFormat: MTLPixelFormat,
        sampleCount: Int) -> MTLRenderPipelineDescriptor {

        let vertexDescriptor = MTLVertexDescriptor()
        
        vertexDescriptor.attributes[0].bufferIndex = 0
        vertexDescriptor.attributes[0].offset = 0
        vertexDescriptor.attributes[0].format = .float3
        
        vertexDescriptor.attributes[1].bufferIndex = 0
        vertexDescriptor.attributes[1].offset = MemoryLayout<float3>.stride
        vertexDescriptor.attributes[1].format = .float3
        
        vertexDescriptor.layouts[0].stride = MemoryLayout<float3>.stride * 2

        let renderPipelineDescriptor = MTLRenderPipelineDescriptor()
        renderPipelineDescriptor.colorAttachments[0].pixelFormat = colorPixelFormat
        renderPipelineDescriptor.depthAttachmentPixelFormat = depthStencilPixelFormat
        renderPipelineDescriptor.vertexFunction = library.makeFunction(name: "vertex_circles")!
        renderPipelineDescriptor.fragmentFunction = library.makeFunction(name: "fragment_circles")!
        renderPipelineDescriptor.vertexDescriptor = vertexDescriptor
        renderPipelineDescriptor.sampleCount = sampleCount
        
        return renderPipelineDescriptor
    }
}

