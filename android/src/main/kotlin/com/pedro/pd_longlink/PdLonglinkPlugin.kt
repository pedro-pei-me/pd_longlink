package com.pedro.pd_longlink

import android.os.Handler
import android.os.Looper
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import io.flutter.plugin.common.EventChannel
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener

class PdLonglinkPlugin :
    FlutterPlugin,
    MethodCallHandler,
    EventChannel.StreamHandler {

    private lateinit var channel: MethodChannel
    private lateinit var eventChannel: EventChannel
    private var eventSink: EventChannel.EventSink? = null
    private val mainHandler = Handler(Looper.getMainLooper())
    private val nextSocketId: AtomicInteger = AtomicInteger(1)
    private val sockets: ConcurrentHashMap<Int, WebSocket> = ConcurrentHashMap()
    private val defaultClient: OkHttpClient = OkHttpClient.Builder().readTimeout(0, TimeUnit.MILLISECONDS).build()

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, "pd_longlink")
        channel.setMethodCallHandler(this)
        eventChannel =
            EventChannel(flutterPluginBinding.binaryMessenger, "pd_longlink/system_websocket_events")
        eventChannel.setStreamHandler(this)
    }

    override fun onMethodCall(
        call: MethodCall,
        result: Result
    ) {
        when (call.method) {
            "getPlatformVersion" -> result.success("Android ${android.os.Build.VERSION.RELEASE}")
            "systemWebSocket.connect" -> handleSystemWebSocketConnect(call, result)
            "systemWebSocket.send" -> handleSystemWebSocketSend(call, result)
            "systemWebSocket.sendBinary" -> handleSystemWebSocketSendBinary(call, result)
            "systemWebSocket.close" -> handleSystemWebSocketClose(call, result)
            else -> result.notImplemented()
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
        eventSink = null
        sockets.values.forEach { ws -> ws.cancel() }
        sockets.clear()
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    private fun handleSystemWebSocketConnect(call: MethodCall, result: Result) {
        val args = call.arguments as? Map<*, *>
        val url = args?.get("url") as? String
        if (url.isNullOrEmpty()) {
            result.error("invalid_args", "url is required", null)
            return
        }

        val headers = args["headers"] as? Map<*, *>
        val connectTimeoutMs = (args["connectTimeoutMs"] as? Number)?.toLong() ?: 20000L

        val socketId = nextSocketId.getAndIncrement()
        val reqBuilder = Request.Builder().url(url)
        headers?.forEach { entry ->
            val k = entry.key?.toString() ?: return@forEach
            val v = entry.value?.toString() ?: return@forEach
            reqBuilder.addHeader(k, v)
        }

        val client =
            defaultClient.newBuilder().connectTimeout(connectTimeoutMs, TimeUnit.MILLISECONDS).build()

        val ws = client.newWebSocket(reqBuilder.build(), object : WebSocketListener() {
            override fun onOpen(webSocket: WebSocket, response: Response) {
                sendEvent(mapOf("socketId" to socketId, "type" to "open"))
            }

            override fun onMessage(webSocket: WebSocket, text: String) {
                sendEvent(mapOf("socketId" to socketId, "type" to "message", "data" to text))
            }

            override fun onMessage(webSocket: WebSocket, bytes: ByteArray) {
                sendEvent(mapOf(
                    "socketId" to socketId,
                    "type" to "message",
                    "isBinary" to true,
                    "dataBytes" to bytes.toList()
                ))
            }

            override fun onClosed(webSocket: WebSocket, code: Int, reason: String) {
                sockets.remove(socketId)
                sendEvent(mapOf("socketId" to socketId, "type" to "closed", "code" to code, "reason" to reason))
            }

            override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) {
                sockets.remove(socketId)
                sendEvent(mapOf("socketId" to socketId, "type" to "error", "error" to t.toString()))
            }
        })

        sockets[socketId] = ws
        result.success(mapOf("socketId" to socketId))
    }

    private fun handleSystemWebSocketSend(call: MethodCall, result: Result) {
        val args = call.arguments as? Map<*, *>
        val socketId = (args?.get("socketId") as? Number)?.toInt()
        val text = args?.get("text") as? String
        if (socketId == null || text == null) {
            result.error("invalid_args", "socketId and text are required", null)
            return
        }

        sockets[socketId]?.send(text)
        result.success(null)
    }

    private fun handleSystemWebSocketSendBinary(call: MethodCall, result: Result) {
        val args = call.arguments as? Map<*, *>
        val socketId = (args?.get("socketId") as? Number)?.toInt()
        val rawBytes = args?.get("bytes")
        if (socketId == null || rawBytes == null) {
            result.error("invalid_args", "socketId and bytes are required", null)
            return
        }
        val bytes: ByteArray = when (rawBytes) {
            is ByteArray -> rawBytes
            is List<*> -> rawBytes.map { (it as? Number)?.toByte() ?: 0 }.toByteArray()
            else -> {
                result.error("invalid_args", "bytes must be ByteArray or List", null)
                return
            }
        }

        sockets[socketId]?.send(bytes)
        result.success(null)
    }

    private fun handleSystemWebSocketClose(call: MethodCall, result: Result) {
        val args = call.arguments as? Map<*, *>
        val socketId = (args?.get("socketId") as? Number)?.toInt()
        if (socketId == null) {
            result.error("invalid_args", "socketId is required", null)
            return
        }

        val code = (args["code"] as? Number)?.toInt() ?: 1000
        val reason = args["reason"] as? String ?: ""
        val ws = sockets.remove(socketId)
        if (ws != null) {
            ws.close(code, reason)
        }
        result.success(null)
    }

    private fun sendEvent(event: Map<String, Any?>) {
        mainHandler.post {
            eventSink?.success(event)
        }
    }
}