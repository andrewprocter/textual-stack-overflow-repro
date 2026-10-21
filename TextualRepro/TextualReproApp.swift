// Minimal reproduction of a main-thread stack overflow in Textual's TextBuilder.
//
// A syntax-highlighted code block becomes one attributed run per token, and
// TextBuilder joins the runs left to right (`a + b + c + …`). SwiftUI resolves that
// chain recursively, one level per run, so a long enough block exhausts the main
// thread's stack (1 MB on iPhone, so roughly 650 runs, or about 55 lines of JSON).
//
// Launch arguments run a case without tapping, e.g.
//   -renderer textual -lines 300 -autoRender YES

import SwiftUI
import Textual

@main
struct TextualReproApp: App {
  var body: some Scene {
    WindowGroup {
      ContentView()
    }
  }
}

enum Renderer: String, CaseIterable, Identifiable, Hashable {
  case textual
  case leftFold
  case balanced

  var id: Self { self }

  var title: String {
    switch self {
    case .textual: "Textual code block"
    case .leftFold: "SwiftUI a + b + c…"
    case .balanced: "SwiftUI balanced"
    }
  }

  var summary: String {
    switch self {
    case .textual:
      "StructuredText rendering a ```json block. Crashes on Textual 0.5.0; renders with the fix."
    case .leftFold:
      "Plain SwiftUI: N colored Text runs joined left to right, as TextBuilder does in 0.5.0. Crashes."
    case .balanced:
      "Plain SwiftUI: the same N runs joined as a balanced tree, as in the fix. Renders."
    }
  }
}

struct RenderRequest: Hashable, Identifiable {
  let renderer: Renderer
  let lines: Int

  var id: Self { self }
}

struct ContentView: View {
  @State private var renderer: Renderer
  @State private var lines: Int
  @State private var request: RenderRequest?

  init() {
    let defaults = UserDefaults.standard
    let renderer = defaults.string(forKey: "renderer").flatMap(Renderer.init(rawValue:)) ?? .textual
    let lines = defaults.integer(forKey: "lines") > 0 ? defaults.integer(forKey: "lines") : 300
    _renderer = State(initialValue: renderer)
    _lines = State(initialValue: lines)
    _request = State(
      initialValue: defaults.bool(forKey: "autoRender")
        ? RenderRequest(renderer: renderer, lines: lines) : nil
    )
  }

  var body: some View {
    NavigationStack {
      Form {
        Section {
          Picker("Renderer", selection: $renderer) {
            ForEach(Renderer.allCases) { Text($0.title).tag($0) }
          }
          Stepper("JSON lines: \(lines)", value: $lines, in: 10...10_000, step: 10)
          LabeledContent("Text runs", value: "≈ \(Sample.approximateRuns(lines: lines))")
        } footer: {
          Text(renderer.summary)
        }
        Section {
          Button("Render") {
            request = RenderRequest(renderer: renderer, lines: lines)
          }
        } footer: {
          Text(
            "On Textual 0.5.0 an iPhone crashes from about 55 lines (≈650 runs, 1 MB stack); "
              + "the iOS 27 simulator, with a larger stack, from about 250 lines."
          )
        }
      }
      .navigationTitle("Textual repro")
      .navigationDestination(item: $request) { RenderView(request: $0) }
    }
  }
}

struct RenderView: View {
  let request: RenderRequest

  var body: some View {
    ScrollView {
      content
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
    }
    .navigationTitle(request.renderer.title)
    .task {
      // Textual tokenizes asynchronously and re-renders with the highlighted runs,
      // so give it time before declaring survival.
      try? await Task.sleep(for: .seconds(3))
      print("REPRO survived renderer=\(request.renderer.rawValue) lines=\(request.lines)")
    }
  }

  @ViewBuilder
  private var content: some View {
    switch request.renderer {
    case .textual:
      StructuredText(markdown: Sample.markdown(lines: request.lines))
    case .leftFold:
      Sample.texts(count: Sample.approximateRuns(lines: request.lines))
        .reduce(Text(verbatim: "")) { $0 + $1 }
        .font(.system(.footnote, design: .monospaced))
    case .balanced:
      Text(balancing: Sample.texts(count: Sample.approximateRuns(lines: request.lines))[...])
        .font(.system(.footnote, design: .monospaced))
    }
  }
}

extension Text {
  init(balancing texts: ArraySlice<Text>) {
    switch texts.count {
    case 0:
      self.init(verbatim: "")
    case 1:
      self = texts[texts.startIndex]
    default:
      let middle = texts.startIndex + texts.count / 2
      self = Text(balancing: texts[..<middle]) + Text(balancing: texts[middle...])
    }
  }
}

enum Sample {
  /// Textual's default theme splits one of these JSON lines into about 12 runs.
  static let runsPerLine = 12

  static func approximateRuns(lines: Int) -> Int {
    lines * runsPerLine
  }

  static func markdown(lines: Int) -> String {
    let rows = (1...lines).map { index in
      #"  {"id": \#(index), "name": "user-\#(index)", "active": \#(index.isMultiple(of: 2)), "score": \#(Double(index) / 4), "tags": ["a", "b"]}"#
    }
    return "A long highlighted code block:\n\n```json\n[\n" + rows.joined(separator: ",\n") + "\n]\n```\n"
  }

  static func texts(count: Int) -> [Text] {
    let colors: [Color] = [.red, .blue, .green, .orange]
    return (0..<count).map { index in
      Text(verbatim: index.isMultiple(of: 24) ? "x\n" : "x ").foregroundStyle(colors[index % colors.count])
    }
  }
}
