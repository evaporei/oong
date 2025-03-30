package oong

import "base:runtime"
import "core:c"
import "core:fmt"
import "core:math"
import "core:slice"
import "core:strings"

import rl "vendor:raylib"
import "./vendor/clay"


clay_ctx: runtime.Context

clay_error_handler :: proc "c" (error_data: clay.ErrorData) {
	context = clay_ctx
	fmt.println("clay_error_handler:", error_data)
}

measureText :: proc "c" (
    text: clay.StringSlice,
    config: ^clay.TextElementConfig,
    userData: rawptr,
) -> clay.Dimensions {
    context = runtime.default_context()

    maxTextWidth: f32 = 0
    lineTextWidth: f32 = 0

    textHeight := cast(f32)config.fontSize

    str := string(text.chars[:text.length])
    // load_missing_codepoints(&g_state.renderer, str, int(config.fontId))

    for codepoint, _ in str {
        if (codepoint == '\n') {
            maxTextWidth = max(maxTextWidth, lineTextWidth)
            lineTextWidth = 0
            continue
        }

        index := rl.GetGlyphIndex(font^, codepoint)

        if (font.glyphs[index].advanceX != 0) {
            lineTextWidth += cast(f32)font.glyphs[index].advanceX
        } else {
            lineTextWidth += (font.recs[index].width + cast(f32)font.glyphs[index].offsetX)
        }
    }

    maxTextWidth = max(maxTextWidth, lineTextWidth)

    return {maxTextWidth, textHeight}
}

clay_measure_text :: proc "c" (
	text: clay.StringSlice,
	config: ^clay.TextElementConfig,
	user_data: rawptr,
) -> (
	text_size: clay.Dimensions,
) {
	text_size = {
            width = c.float(text.length * i32(config.fontSize)), // <- this will only work for monospace fonts, see the renderers/ directory for more advanced text measurement
            height = c.float(config.fontSize)
    }

	// max_text_width, line_text_width: f32
    //
	// text_height := f32(config.fontSize)
	// font_to_use := font
    //
	// for i in 0 ..< int(text.length) {
	// 	if text.chars[i] == '\n' {
	// 		max_text_width = max(max_text_width, line_text_width)
	// 		line_text_width = 0
	// 		continue
	// 	}
	// 	index := i32(text.chars[i] - 32)
	// 	if font_to_use.glyphs[index].advanceX != 0 {
	// 		line_text_width += f32(font_to_use.glyphs[index].advanceX)
	// 	} else {
	// 		line_text_width +=
	// 			(font_to_use.recs[index].width + f32(font_to_use.glyphs[index].offsetX))
	// 	}
	// }
    //
	// max_text_width = max(max_text_width, line_text_width)
    //
	// text_size.width = max_text_width / 2
	// text_size.height = text_height

	return
}

GAME_WIDTH, GAME_HEIGHT :: 1920, 1080
FONT_SIZE :: 50
FONT_SPACING :: 2

font: ^rl.Font

main :: proc() {
	rl.SetTraceLogLevel(.ERROR)
		clay_min_memory_size := clay.MinMemorySize()
	clay_memory := make([^]u8, clay_min_memory_size)
	clay_arena := clay.CreateArenaWithCapacityAndMemory(clay_min_memory_size, clay_memory)
	clay.Initialize(
		clay_arena,
		// NOTE(eva): this is {0, 0} btw :thinking: -> even tried calling it after InitWindow
		clay.Dimensions{f32(rl.GetScreenWidth()), f32(rl.GetScreenHeight())},
		clay.ErrorHandler{handler = clay_error_handler},
	)
	clay.SetMeasureTextFunction(measureText, nil)

	// NOTE(eva): idk if we want this helps at all
	rl.SetConfigFlags({.VSYNC_HINT, .WINDOW_HIGHDPI, .MSAA_4X_HINT})
	rl.InitWindow(GAME_WIDTH, GAME_HEIGHT, "oong")
	defer rl.CloseWindow()

	// font = rl.LoadFont("Roboto Regular.ttf")
	font = new(rl.Font)
	font^ = rl.LoadFontEx("Roboto Regular.ttf", FONT_SIZE, nil, 0)
	rl.SetTextureFilter(font^.texture, rl.TextureFilter.TRILINEAR)

	// font = rl.LoadFont("font.ttf")

	clay_debug_mode := false

	for !rl.WindowShouldClose() {
		defer free_all(context.temp_allocator)

		if rl.IsKeyPressed(.D) {
			clay_debug_mode = !clay_debug_mode
			clay.SetDebugModeEnabled(clay_debug_mode)
		}
		clay.SetPointerState(
			transmute(clay.Vector2)rl.GetMousePosition(),
			rl.IsMouseButtonDown(.LEFT),
		)
		clay.UpdateScrollContainers(
			false,
			transmute(clay.Vector2)rl.GetMouseWheelMoveV(),
			rl.GetFrameTime(),
		)
		clay.SetLayoutDimensions({cast(f32)rl.GetScreenWidth(), cast(f32)rl.GetScreenHeight()})

		clay.BeginLayout()
		if clay.UI()({
			id = clay.ID("Game"),
			layout = {
				layoutDirection = .TopToBottom,
				sizing = {clay.SizingGrow({}), clay.SizingGrow({})},
				childAlignment = clay.ChildAlignment{x = .Center},
			},
			backgroundColor = rl_to_clay_color(rl.BLACK),
		}) {
			if clay.UI()({
				id = clay.ID("DebugTextRectangle"),
				// layout = {
				// 	childAlignment = clay.ChildAlignment{x = .Center},
				// },
				backgroundColor = rl_to_clay_color(rl.RED),
			}) {
				clay.Text("oong", clay.TextConfig({
					fontSize = FONT_SIZE,
					letterSpacing = FONT_SPACING,
					textColor = rl_to_clay_color(rl.WHITE),
					textAlignment = .Center,
				}))
			}
		}

		render_cmds := clay.EndLayout()

		rl.BeginDrawing()
		defer rl.EndDrawing()

		clay_rl_render(&render_cmds)

		// rl.DrawFPS(0, 0)
	}
}

clay_to_rl_color :: proc(color: clay.Color) -> rl.Color {
	return rl.Color{cast(u8)color.r, cast(u8)color.g, cast(u8)color.b, cast(u8)color.a}
}

rl_to_clay_color :: proc(color: rl.Color) -> clay.Color {
	return clay.Color{cast(f32)color.r, cast(f32)color.g, cast(f32)color.b, cast(f32)color.a}
}

clay_rl_render :: proc(
	render_cmds: ^clay.ClayArray(clay.RenderCommand),
	allocator := context.temp_allocator,
) {
	for i in 0 ..< int(render_cmds.length) {
		render_cmd := clay.RenderCommandArray_Get(render_cmds, cast(i32)i)
		// fmt.println(render_cmd)
		bounding_box := render_cmd.boundingBox
		switch (render_cmd.commandType) {
		case .None:
			{}
		case .Text:
			config := render_cmd.renderData.text
			// Raylib uses standard C strings so isn't compatible with cheap slices, we need to clone the string to append null terminator
			text := string(config.stringContents.chars[:config.stringContents.length])
			cloned := strings.clone_to_cstring(text, allocator)
			font_to_use := font^
			rl.DrawTextEx(
				font_to_use,
				cloned,
				rl.Vector2{bounding_box.x, bounding_box.y},
				cast(f32)config.fontSize,
				cast(f32)config.letterSpacing,
				clay_to_rl_color(config.textColor),
			)
		case .Image:
			config := render_cmd.renderData.image
			tint_color := config.backgroundColor
			if tint_color.rgba == 0 do tint_color = {255, 255, 255, 255}

			// TODO image handling
			image_texture := cast(^rl.Texture2D)config.imageData
			rl.DrawTextureEx(
				image_texture^,
				rl.Vector2{bounding_box.x, bounding_box.y},
				0,
				bounding_box.width / cast(f32)image_texture.width,
				clay_to_rl_color(tint_color),
			)
		case .ScissorStart:
			rl.BeginScissorMode(
				cast(i32)math.round(bounding_box.x),
				cast(i32)math.round(bounding_box.y),
				cast(i32)math.round(bounding_box.width),
				cast(i32)math.round(bounding_box.height),
			)
		case .ScissorEnd:
			rl.EndScissorMode()
		case .Rectangle:
			config := render_cmd.renderData.rectangle
			if config.cornerRadius.topLeft > 0 {
				radius: f32 =
					(config.cornerRadius.topLeft * 2) /
					min(bounding_box.width, bounding_box.height)
				rl.DrawRectangleRounded(
					rl.Rectangle {
						bounding_box.x,
						bounding_box.y,
						bounding_box.width,
						bounding_box.height,
					},
					radius,
					8,
					clay_to_rl_color(config.backgroundColor),
				)
			} else {
				rl.DrawRectangle(
					cast(i32)bounding_box.x,
					cast(i32)bounding_box.y,
					cast(i32)bounding_box.width,
					cast(i32)bounding_box.height,
					clay_to_rl_color(config.backgroundColor),
				)
			}
		case .Border:
			config := render_cmd.renderData.border
			// Left border
			if config.width.left > 0 {
				rl.DrawRectangle(
					cast(i32)math.round(bounding_box.x),
					cast(i32)math.round(bounding_box.y + config.cornerRadius.topLeft),
					cast(i32)config.width.left,
					cast(i32)math.round(
						bounding_box.height -
						config.cornerRadius.topLeft -
						config.cornerRadius.bottomLeft,
					),
					clay_to_rl_color(config.color),
				)
			}
			// Right border
			if config.width.right > 0 {
				rl.DrawRectangle(
					cast(i32)math.round(
						bounding_box.x + bounding_box.width - cast(f32)config.width.right,
					),
					cast(i32)math.round(bounding_box.y + config.cornerRadius.topRight),
					cast(i32)config.width.right,
					cast(i32)math.round(
						bounding_box.height -
						config.cornerRadius.topRight -
						config.cornerRadius.bottomRight,
					),
					clay_to_rl_color(config.color),
				)
			}
			// Top border
			if config.width.top > 0 {
				rl.DrawRectangle(
					cast(i32)math.round(bounding_box.x + config.cornerRadius.topLeft),
					cast(i32)math.round(bounding_box.y),
					cast(i32)math.round(
						bounding_box.width -
						config.cornerRadius.topLeft -
						config.cornerRadius.topRight,
					),
					cast(i32)config.width.top,
					clay_to_rl_color(config.color),
				)
			}
			// Bottom border
			if config.width.bottom > 0 {
				rl.DrawRectangle(
					cast(i32)math.round(bounding_box.x + config.cornerRadius.bottomLeft),
					cast(i32)math.round(
						bounding_box.y + bounding_box.height - cast(f32)config.width.bottom,
					),
					cast(i32)math.round(
						bounding_box.width -
						config.cornerRadius.bottomLeft -
						config.cornerRadius.bottomRight,
					),
					cast(i32)config.width.bottom,
					clay_to_rl_color(config.color),
				)
			}
			if config.cornerRadius.topLeft > 0 {
				rl.DrawRing(
					rl.Vector2 {
						math.round(bounding_box.x + config.cornerRadius.topLeft),
						math.round(bounding_box.y + config.cornerRadius.topLeft),
					},
					math.round(config.cornerRadius.topLeft - cast(f32)config.width.top),
					config.cornerRadius.topLeft,
					180,
					270,
					10,
					clay_to_rl_color(config.color),
				)
			}
			if config.cornerRadius.topRight > 0 {
				rl.DrawRing(
					rl.Vector2 {
						math.round(
							bounding_box.x + bounding_box.width - config.cornerRadius.topRight,
						),
						math.round(bounding_box.y + config.cornerRadius.topRight),
					},
					math.round(config.cornerRadius.topRight - cast(f32)config.width.top),
					config.cornerRadius.topRight,
					270,
					360,
					10,
					clay_to_rl_color(config.color),
				)
			}
			if config.cornerRadius.bottomLeft > 0 {
				rl.DrawRing(
					rl.Vector2 {
						math.round(bounding_box.x + config.cornerRadius.bottomLeft),
						math.round(
							bounding_box.y + bounding_box.height - config.cornerRadius.bottomLeft,
						),
					},
					math.round(config.cornerRadius.bottomLeft - cast(f32)config.width.top),
					config.cornerRadius.bottomLeft,
					90,
					180,
					10,
					clay_to_rl_color(config.color),
				)
			}
			if config.cornerRadius.bottomRight > 0 {
				rl.DrawRing(
					rl.Vector2 {
						math.round(
							bounding_box.x + bounding_box.width - config.cornerRadius.bottomRight,
						),
						math.round(
							bounding_box.y + bounding_box.height - config.cornerRadius.bottomRight,
						),
					},
					math.round(config.cornerRadius.bottomRight - cast(f32)config.width.bottom),
					config.cornerRadius.bottomRight,
					0.1,
					90,
					10,
					clay_to_rl_color(config.color),
				)
			}
		case .Custom:
		// Implement custom element rendering here
		}
	}
}
