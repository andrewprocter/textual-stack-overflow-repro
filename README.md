# Textual stack overflow repro

A one-screen iOS app that crashes [Textual](https://github.com/gonzalezreal/textual) 0.5.0 with a long syntax-highlighted code block, and shows the same content rendering once the fix in [gonzalezreal/textual#92](https://github.com/gonzalezreal/textual/pull/92) is applied.

## What goes wrong

Textual's highlighter turns every token of a code block into its own styled run. `TextBuilder` then joins the runs one after another, `a + b + c + …`, so the resulting `Text` is nested one level deeper for each run. SwiftUI walks that nesting recursively when it draws (`Text.resolve` → `ConcatenatedTextStorage.resolve` → `Text.Storage.resolve`, over and over), and a long enough block runs the main thread out of stack:

```
Exception Type:  EXC_BAD_ACCESS (SIGSEGV)
Exception Message: Thread stack size exceeded due to excessive recursion
0     libsystem_pthread.dylib  ___chkstk_darwin
1     SwiftUICore              Text.resolve<A>(into:in:with:)
2     SwiftUICore              ConcatenatedTextStorage.resolve<A>(into:in:with:)
3     SwiftUICore              Text.Storage.resolve<A>(into:in:with:)
...   (the same three frames, about 660 times)
```

That excerpt is from a production crash on an iPhone 15 Pro running iOS 27. An iPhone's main thread has a 1 MB stack, which runs out at roughly 650 runs. Highlighted JSON comes to about 12 runs a line and Swift about 5, so 55 lines of JSON or 130 lines of Swift in a single block are enough to crash. The highlighter works asynchronously, so the crash lands a moment after the block appears.

## Run it

| Project | Textual | Result |
| --- | --- | --- |
| `TextualRepro.xcodeproj` | 0.5.0 | crashes |
| `TextualRepro-Fixed.xcodeproj` | [`fix/balanced-text-concatenation`](https://github.com/andrewprocter/textual/tree/fix/balanced-text-concatenation) | renders |

Open either project, run it, pick a renderer and a line count, and tap **Render**. The renderers:

- **Textual code block**: `StructuredText` rendering a fenced `json` block of N lines. This is the real-world case.
- **SwiftUI a + b + c…**: no Textual involved. N×12 colored `Text` runs joined left to right, which is what `TextBuilder` does today. Crashes on both projects, because it's SwiftUI's behavior.
- **SwiftUI balanced**: the same runs joined as a balanced tree, which is the fix. The nesting is about log₂(N) deep, so it never crashes.

The simulator's main thread has a larger stack than a phone's, so it needs bigger blocks than a device. Measured on an iPhone 17 Pro simulator, iOS 27.0:

| Renderer | Textual 0.5.0 | With the fix |
| --- | --- | --- |
| Textual code block, 200 lines (≈2,400 runs) | renders | renders |
| Textual code block, 250 lines (≈3,000 runs) | **crashes** | renders |
| Textual code block, 300 lines (≈3,600 runs) | **crashes** | renders, identical to 0.5.0 at smaller sizes |
| SwiftUI a + b + c…, ≈3,600 runs | renders | renders |
| SwiftUI a + b + c…, ≈7,200 runs | **crashes** | **crashes** (plain SwiftUI, no Textual) |
| SwiftUI balanced, ≈24,000 runs | renders | renders |

On a device, start at 60 lines with the Textual renderer.

### Without tapping

Launch arguments run a case directly. The app prints `REPRO survived …` three seconds after rendering:

```bash
xcrun simctl launch --console-pty booted com.example.TextualRepro -renderer textual -lines 300 -autoRender YES
```

`-renderer` is `textual`, `leftFold` or `balanced`.

## The fix

[`TextBuilder.swift`](https://github.com/andrewprocter/textual/blob/fix/balanced-text-concatenation/Sources/Textual/Internal/TextFragment/TextBuilder.swift) joins each half of the runs first, then the two halves, instead of folding left to right. The text and its attributes come out the same. Only the nesting changes, from N levels deep to about log₂(N).
