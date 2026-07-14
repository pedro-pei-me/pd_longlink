import Flutter
import UIKit

public class PdLonglinkPlugin: NSObject, FlutterPlugin, FlutterStreamHandler, URLSessionWebSocketDelegate {
  private var eventSink: FlutterEventSink?
  private var nextSocketId: Int = 1
  private var tasks: [Int: URLSessionWebSocketTask] = [:]
  private var taskIdToSocketId: [Int: Int] = [:]

  private lazy var session: URLSession = {
    return URLSession(configuration: URLSessionConfiguration.default, delegate: self, delegateQueue: nil)
  }()

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "pd_longlink", binaryMessenger: registrar.messenger())
    let instance = PdLonglinkPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)

    let eventChannel = FlutterEventChannel(name: "pd_longlink/system_websocket_events", binaryMessenger: registrar.messenger())
    eventChannel.setStreamHandler(instance)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "getPlatformVersion":
      result("iOS " + UIDevice.current.systemVersion)
    case "systemWebSocket.connect":
      handleSystemWebSocketConnect(call, result: result)
    case "systemWebSocket.send":
      handleSystemWebSocketSend(call, result: result)
    case "systemWebSocket.sendBinary":
      handleSystemWebSocketSendBinary(call, result: result)
    case "systemWebSocket.close":
      handleSystemWebSocketClose(call, result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    eventSink = events
    return nil
  }

  public func onCancel(withArguments arguments: Any?) -> FlutterError? {
    eventSink = nil
    return nil
  }

  private func handleSystemWebSocketConnect(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any] else {
      result(FlutterError(code: "invalid_args", message: "arguments must be a map", details: nil))
      return
    }
    guard let urlString = args["url"] as? String, let url = URL(string: urlString) else {
      result(FlutterError(code: "invalid_args", message: "url is required", details: nil))
      return
    }

    let headers = args["headers"] as? [String: Any]
    let connectTimeoutMs = (args["connectTimeoutMs"] as? NSNumber)?.doubleValue ?? 20000

    var request = URLRequest(url: url)
    request.timeoutInterval = connectTimeoutMs / 1000.0
    headers?.forEach { (key: String, value: Any) in
      request.setValue("\(value)", forHTTPHeaderField: key)
    }

    let socketId = nextSocketId
    nextSocketId += 1

    let task = session.webSocketTask(with: request)
    tasks[socketId] = task
    taskIdToSocketId[task.taskIdentifier] = socketId
    task.resume()
    receiveLoop(socketId: socketId, task: task)
    result(["socketId": socketId])
  }

  private func handleSystemWebSocketSend(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any] else {
      result(FlutterError(code: "invalid_args", message: "arguments must be a map", details: nil))
      return
    }
    guard let socketId = args["socketId"] as? Int, let text = args["text"] as? String else {
      result(FlutterError(code: "invalid_args", message: "socketId and text are required", details: nil))
      return
    }
    guard let task = tasks[socketId] else {
      result(nil)
      return
    }
    task.send(.string(text)) { error in
      if let error = error {
        self.sendEvent(["socketId": socketId, "type": "error", "error": error.localizedDescription])
      }
      result(nil)
    }
  }

  private func handleSystemWebSocketSendBinary(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any] else {
      result(FlutterError(code: "invalid_args", message: "arguments must be a map", details: nil))
      return
    }
    guard let socketId = args["socketId"] as? Int, let bytes = args["bytes"] as? FlutterStandardTypedData else {
      result(FlutterError(code: "invalid_args", message: "socketId and bytes are required", details: nil))
      return
    }
    guard let task = tasks[socketId] else {
      result(nil)
      return
    }
    task.send(.data(bytes.data)) { error in
      if let error = error {
        self.sendEvent(["socketId": socketId, "type": "error", "error": error.localizedDescription])
      }
      result(nil)
    }
  }

  private func handleSystemWebSocketClose(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any] else {
      result(FlutterError(code: "invalid_args", message: "arguments must be a map", details: nil))
      return
    }
    guard let socketId = args["socketId"] as? Int else {
      result(FlutterError(code: "invalid_args", message: "socketId is required", details: nil))
      return
    }
    let code = (args["code"] as? Int) ?? 1000
    let reason = (args["reason"] as? String) ?? ""

    if let task = tasks.removeValue(forKey: socketId) {
      taskIdToSocketId.removeValue(forKey: task.taskIdentifier)
      task.cancel(with: URLSessionWebSocketTask.CloseCode(rawValue: code) ?? .normalClosure, reason: reason.data(using: .utf8))
    }
    result(nil)
  }

  private func receiveLoop(socketId: Int, task: URLSessionWebSocketTask) {
    task.receive { res in
      switch res {
      case .failure(let error):
        self.tasks.removeValue(forKey: socketId)
        self.sendEvent(["socketId": socketId, "type": "error", "error": error.localizedDescription])
      case .success(let message):
        switch message {
        case .string(let text):
          self.sendEvent(["socketId": socketId, "type": "message", "data": text])
        case .data(let data):
          self.sendEvent([
            "socketId": socketId,
            "type": "message",
            "isBinary": true,
            "dataBytes": FlutterStandardTypedData(bytes: data)
          ])
        @unknown default:
          break
        }
        self.receiveLoop(socketId: socketId, task: task)
      }
    }
  }

  public func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
    if let socketId = taskIdToSocketId[webSocketTask.taskIdentifier] {
      sendEvent(["socketId": socketId, "type": "open"])
    }
  }

  public func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
    if let socketId = taskIdToSocketId[webSocketTask.taskIdentifier] {
      tasks.removeValue(forKey: socketId)
      taskIdToSocketId.removeValue(forKey: webSocketTask.taskIdentifier)
      let reasonText = reason.flatMap { String(data: $0, encoding: .utf8) } ?? ""
      sendEvent(["socketId": socketId, "type": "closed", "code": closeCode.rawValue, "reason": reasonText])
    }
  }

  private func sendEvent(_ event: [String: Any]) {
    eventSink?(event)
  }
}