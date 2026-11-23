#include "engine/engine.h"

#include <SDL3/SDL.h>
#ifdef NDEBUG
#undef NDEBUG
#endif
#include <assert.h>
#include <math.h>
#include <stdio.h>
#include <string.h>

static void dummy_nop(void) {}
static const char *g_fail_sym = NULL;

static eng_gl_proc_t fake_gl_loader(const char *name) {
    if (g_fail_sym && strcmp(name, g_fail_sym) == 0) {
        return NULL;
    }
    return dummy_nop;
}

static void test_gl_loader_and_mock(void) {
    assert(!eng_gl_load(NULL, false));
    g_fail_sym = "glDrawElementsInstanced";
    assert(!eng_gl_load(fake_gl_loader, false));
    g_fail_sym = NULL;
    assert(eng_gl_load(fake_gl_loader, true));
    assert(eng_gl()->is_gles && !eng_gl()->is_mock);

    eng_gl_init_software_mock();
    const eng_gl_api_t *gl = eng_gl();
    assert(gl->is_mock);
    eng_gl_mock_reset_stats();

    gl->Viewport(0, 0, 640, 480);
    gl->Scissor(0, 0, 640, 480);
    gl->ClearColor(0.2f, 0.4f, 0.8f, 1.0f);
    gl->Clear(ENG_GL_COLOR_BUFFER_BIT | ENG_GL_DEPTH_BUFFER_BIT);
    gl->Enable(ENG_GL_DEPTH_TEST);
    gl->Disable(ENG_GL_BLEND);
    gl->DepthFunc(ENG_GL_LEQUAL);
    gl->DepthMask(ENG_GL_TRUE);
    gl->BlendFunc(ENG_GL_SRC_ALPHA, ENG_GL_ONE_MINUS_SRC_ALPHA);
    gl->CullFace(ENG_GL_BACK);

    GLuint vbo = 0, vao = 0, tex = 0, fbo = 0, qid = 0;
    gl->GenBuffers(1, &vbo);
    gl->BindBuffer(ENG_GL_ARRAY_BUFFER, vbo);
    float tri[9] = {0};
    gl->BufferData(ENG_GL_ARRAY_BUFFER, sizeof(tri), tri, ENG_GL_STATIC_DRAW);
    gl->BufferSubData(ENG_GL_ARRAY_BUFFER, 0, sizeof(tri), tri);
    gl->BindBufferBase(ENG_GL_UNIFORM_BUFFER, 0, vbo);

    gl->GenVertexArrays(1, &vao);
    gl->BindVertexArray(vao);
    gl->EnableVertexAttribArray(0);
    gl->VertexAttribPointer(0, 3, ENG_GL_FLOAT, ENG_GL_FALSE, 12, NULL);
    gl->VertexAttribDivisor(0, 1);

    GLuint vs = gl->CreateShader(ENG_GL_VERTEX_SHADER);
    const char *src = "void main(){}";
    gl->ShaderSource(vs, 1, &src, NULL);
    gl->CompileShader(vs);
    GLint ok = 0; char log[64]; GLsizei log_len = 0;
    gl->GetShaderiv(vs, ENG_GL_COMPILE_STATUS, &ok);
    gl->GetShaderInfoLog(vs, sizeof(log), &log_len, log);
    assert(ok == 1 && log_len == 0);

    GLuint prog = gl->CreateProgram();
    gl->AttachShader(prog, vs);
    gl->LinkProgram(prog);
    gl->GetProgramiv(prog, ENG_GL_LINK_STATUS, &ok);
    gl->GetProgramInfoLog(prog, sizeof(log), &log_len, log);
    gl->UseProgram(prog);
    assert(gl->GetUniformLocation(prog, "u_mvp") == 0);
    assert(gl->GetUniformBlockIndex(prog, "PerFrame") == 0);
    gl->UniformBlockBinding(prog, 0, 0);
    gl->Uniform1i(0, 1);
    gl->Uniform1f(0, 0.5f);
    gl->Uniform3fv(0, 1, tri);
    gl->Uniform4fv(0, 1, tri);
    eng_mat4_t id = eng_mat4_identity();
    gl->UniformMatrix4fv(0, 1, ENG_GL_FALSE, id.m);

    gl->ActiveTexture(ENG_GL_TEXTURE0);
    gl->GenTextures(1, &tex);
    gl->BindTexture(ENG_GL_TEXTURE_2D, tex);
    uint8_t px[16] = {255};
    gl->TexImage2D(ENG_GL_TEXTURE_2D, 0, ENG_GL_RGBA8, 2, 2, 0, ENG_GL_RGBA, ENG_GL_UNSIGNED_BYTE, px);
    gl->TexSubImage2D(ENG_GL_TEXTURE_2D, 0, 0, 0, 2, 2, ENG_GL_RGBA, ENG_GL_UNSIGNED_BYTE, px);
    gl->TexParameteri(ENG_GL_TEXTURE_2D, ENG_GL_TEXTURE_MIN_FILTER, ENG_GL_NEAREST);
    gl->GenerateMipmap(ENG_GL_TEXTURE_2D);

    gl->GenFramebuffers(1, &fbo);
    gl->BindFramebuffer(ENG_GL_FRAMEBUFFER, fbo);
    gl->FramebufferTexture2D(ENG_GL_FRAMEBUFFER, ENG_GL_COLOR_ATTACHMENT0, ENG_GL_TEXTURE_2D, tex, 0);
    GLenum att = ENG_GL_COLOR_ATTACHMENT0;
    gl->DrawBuffers(1, &att);
    assert(gl->CheckFramebufferStatus(ENG_GL_FRAMEBUFFER) == ENG_GL_FRAMEBUFFER_COMPLETE);
    uint8_t read_px[16] = {0};
    gl->ReadPixels(0, 0, 2, 2, ENG_GL_RGBA, ENG_GL_UNSIGNED_BYTE, read_px);
    assert(read_px[3] == 255 && read_px[2] > read_px[0]);

    gl->GenQueries(1, &qid);
    gl->BeginQuery(ENG_GL_ANY_SAMPLES_PASSED_CONSERVATIVE, qid);
    gl->DrawArrays(ENG_GL_TRIANGLES, 0, 3);
    gl->DrawElements(ENG_GL_TRIANGLES, 3, ENG_GL_UNSIGNED_SHORT, NULL);
    gl->DrawElementsInstanced(ENG_GL_TRIANGLES, 3, ENG_GL_UNSIGNED_INT, NULL, 10);
    gl->EndQuery(ENG_GL_ANY_SAMPLES_PASSED_CONSERVATIVE);
    GLuint visible = 0;
    gl->GetQueryObjectuiv(qid, ENG_GL_QUERY_RESULT, &visible);
    assert(visible == 1u && eng_gl_mock_draw_calls() == 3u);
    assert(gl->GetError() == 0);

    gl->DeleteQueries(1, &qid);
    gl->DeleteFramebuffers(1, &fbo);
    gl->DeleteTextures(1, &tex);
    gl->DeleteShader(vs);
    gl->DeleteProgram(prog);
    gl->DeleteVertexArrays(1, &vao);
    gl->DeleteBuffers(1, &vbo);
}

static void test_platform_and_input_and_xr(void) {
    eng_platform_config_t cfg = eng_platform_default_config();
    cfg.headless = true;
    cfg.width = 800;
    cfg.height = 600;
    eng_platform_t *plat = eng_platform_create(&cfg);
    assert(plat != NULL && eng_platform_is_headless(plat));
    int w = 0, h = 0, pw = 0, ph = 0;
    eng_platform_get_size(plat, &w, &h);
    eng_platform_get_pixel_size(plat, &pw, &ph);
    assert(w == 800 && h == 600 && pw == 800 && ph == 600);
    assert(fabsf(eng_platform_dpi_scale(plat) - 1.0f) < 0.01f);

    assert(eng_platform_set_size(plat, 1024, 768));
    assert(!eng_platform_set_size(plat, -1, 0));
    assert(eng_platform_set_fullscreen(plat, true));
    assert(eng_platform_set_vsync(plat, 1));
    int displays = eng_platform_display_count();
    if (displays > 0) {
        eng_platform_move_to_display(plat, 0);
    }
    assert(!eng_platform_move_to_display(plat, 999));
    float dt = eng_platform_begin_frame(plat);
    assert(fabsf(dt - (1.0f / 60.0f)) < 1e-4f);
    eng_platform_swap(plat);

    /* Non-headless creation path (gracefully falls back on headless dummy driver) */
    eng_platform_config_t cfg2 = eng_platform_default_config();
    cfg2.fullscreen = false;
    cfg2.borderless = true;
    eng_platform_t *plat2 = eng_platform_create(&cfg2);
    assert(plat2 != NULL);
    eng_platform_begin_frame(plat2);
    eng_platform_destroy(plat2);

    /* Input: Keyboard, Mouse, Gamepad, Touch, Buffer, Coyote, JSON Rebinding */
    eng_input_t *inp = eng_input_create();
    eng_input_begin_frame(inp, dt);

    SDL_Event ev;
    memset(&ev, 0, sizeof(ev));
    ev.type = SDL_EVENT_KEY_DOWN;
    ev.key.scancode = SDL_SCANCODE_SPACE;
    SDL_PushEvent(&ev);

    ev.type = SDL_EVENT_KEY_DOWN;
    ev.key.scancode = SDL_SCANCODE_D;
    SDL_PushEvent(&ev);

    ev.type = SDL_EVENT_MOUSE_MOTION;
    ev.motion.x = 200.0f; ev.motion.y = 150.0f;
    ev.motion.xrel = 12.0f; ev.motion.yrel = -4.0f;
    SDL_PushEvent(&ev);

    ev.type = SDL_EVENT_MOUSE_BUTTON_DOWN;
    ev.button.button = 1;
    SDL_PushEvent(&ev);

    ev.type = SDL_EVENT_MOUSE_WHEEL;
    ev.wheel.y = 2.0f;
    SDL_PushEvent(&ev);

    eng_input_poll_sdl(inp, plat);
    assert(eng_input_down(inp, "jump") && eng_input_pressed(inp, "jump"));
    assert(eng_input_down(inp, "fire"));
    assert(eng_input_axis(inp, "move_x") > 0.9f);
    assert(fabsf(eng_input_mouse_pos(inp).x - 200.0f) < 0.01f);
    assert(fabsf(eng_input_mouse_delta(inp).x - 12.0f) < 0.01f);
    assert(fabsf(eng_input_mouse_wheel(inp) - 2.0f) < 0.01f);

    /* Input buffer persists across a few frames until consumed */
    eng_input_begin_frame(inp, 0.05f);
    ev.type = SDL_EVENT_KEY_UP;
    ev.key.scancode = SDL_SCANCODE_SPACE;
    eng_input_process_event(inp, plat, &ev);
    assert(eng_input_released(inp, "jump"));
    assert(eng_input_buffered(inp, "jump", 0.12f));
    eng_input_consume_buffer(inp, "jump");
    assert(!eng_input_buffered(inp, "jump", 0.12f));

    /* Coyote timer */
    float coyote = 0.0f;
    assert(eng_input_update_coyote(&coyote, true, 0.016f, 0.10f));
    assert(eng_input_update_coyote(&coyote, false, 0.05f, 0.10f));
    assert(!eng_input_update_coyote(&coyote, false, 0.08f, 0.10f));

    /* Gamepad + Mobile Touch events */
    ev.type = SDL_EVENT_KEY_UP; ev.key.scancode = SDL_SCANCODE_D;
    eng_input_process_event(inp, plat, &ev);
    ev.type = SDL_EVENT_MOUSE_BUTTON_UP; ev.button.button = 1;
    eng_input_process_event(inp, plat, &ev);

    ev.type = SDL_EVENT_GAMEPAD_AXIS_MOTION;
    ev.gaxis.axis = SDL_GAMEPAD_AXIS_LEFTY;
    ev.gaxis.value = -32767;
    eng_input_process_event(inp, plat, &ev);
    assert(eng_input_axis(inp, "move_y") > 0.9f);
    ev.gaxis.value = 0;
    eng_input_process_event(inp, plat, &ev);

    ev.type = SDL_EVENT_GAMEPAD_BUTTON_DOWN;
    ev.gbutton.button = SDL_GAMEPAD_BUTTON_SOUTH;
    eng_input_process_event(inp, plat, &ev);
    assert(eng_input_down(inp, "jump"));
    ev.type = SDL_EVENT_GAMEPAD_BUTTON_UP;
    eng_input_process_event(inp, plat, &ev);

    eng_input_set_touch_preset(inp, ENG_TOUCH_DUAL_STICK);
    assert(eng_input_get_touch_preset(inp) == ENG_TOUCH_DUAL_STICK);
    assert(!eng_input_is_touch_active(inp));

    /* Left-side virtual thumbstick + Right-side virtual jump button */
    memset(&ev, 0, sizeof(ev));
    ev.type = SDL_EVENT_FINGER_DOWN;
    ev.tfinger.fingerID = 1; ev.tfinger.x = 0.2f; ev.tfinger.y = 0.5f;
    eng_input_process_event(inp, plat, &ev);
    ev.type = SDL_EVENT_FINGER_MOTION;
    ev.tfinger.fingerID = 1; ev.tfinger.x = 0.35f; ev.tfinger.y = 0.35f;
    eng_input_process_event(inp, plat, &ev);
    assert(eng_input_is_touch_active(inp));
    assert(eng_input_axis(inp, "move_x") > 0.5f && eng_input_axis(inp, "move_y") > 0.5f);

    ev.type = SDL_EVENT_FINGER_DOWN;
    ev.tfinger.fingerID = 2; ev.tfinger.x = 0.85f; ev.tfinger.y = 0.85f;
    eng_input_process_event(inp, plat, &ev);
    assert(eng_input_down(inp, "jump"));
    ev.type = SDL_EVENT_FINGER_MOTION;
    ev.tfinger.fingerID = 2; ev.tfinger.x = 0.86f; ev.tfinger.y = 0.86f; ev.tfinger.dx = 0.02f;
    eng_input_process_event(inp, plat, &ev);
    ev.type = SDL_EVENT_FINGER_UP; ev.tfinger.fingerID = 1;
    eng_input_process_event(inp, plat, &ev);
    ev.type = SDL_EVENT_FINGER_UP; ev.tfinger.fingerID = 2;
    eng_input_process_event(inp, plat, &ev);
    assert(!eng_input_down(inp, "jump"));

    /* JSON action rebinding round-trip */
    assert(eng_input_bind_key(inp, "jump", SDL_SCANCODE_J));
    char bind_json[1024], err[256];
    assert(eng_input_save_bindings_json(inp, bind_json, sizeof(bind_json)) > 0);
    eng_input_t *inp2 = eng_input_create();
    assert(eng_input_load_bindings_json(inp2, bind_json, err, sizeof(err)));
    assert(!eng_input_load_bindings_json(inp2, "{\"bad\":[]}", err, sizeof(err)));
    eng_input_destroy(inp2);

    /* Stereo WebXR Bridge */
    eng_xr_t *xr = eng_xr_create();
    assert(!eng_xr_is_supported(xr) && !eng_xr_is_active(xr));
    eng_xr_set_mode(xr, ENG_XR_DIORAMA);
    assert(eng_xr_get_mode(xr) == ENG_XR_DIORAMA);
    eng_xr_set_diorama_scale(xr, 10.0f);
    assert(eng_xr_request_session(xr) && eng_xr_is_active(xr));

    eng_xr_pose_t head = {eng_v3(0.0f, 1.6f, 0.0f), eng_quat_identity(), true};
    eng_xr_eye_t eyes[2];
    eyes[0].view = eng_mat4_look_at(eng_v3(-0.032f, 1.6f, 0.0f), eng_v3(-0.032f, 1.6f, -1.0f), eng_v3(0, 1, 0));
    eyes[0].proj = eng_mat4_perspective(90.0f * ENG_DEG2RAD, 1.0f, 0.05f, 100.0f);
    eyes[0].viewport[0] = 0; eyes[0].viewport[1] = 0; eyes[0].viewport[2] = 1024; eyes[0].viewport[3] = 1024;
    eyes[1] = eyes[0];
    eyes[1].viewport[0] = 1024;

    eng_xr_hand_t hands[2];
    memset(hands, 0, sizeof(hands));
    hands[0].pose = (eng_xr_pose_t){eng_v3(-0.2f, 1.2f, -0.3f), eng_quat_identity(), true};
    hands[0].thumbstick = (eng_vec2_t){-0.75f, 0.5f};
    hands[1].pose = (eng_xr_pose_t){eng_v3(0.2f, 1.2f, -0.3f), eng_quat_identity(), true};
    hands[1].trigger = 0.9f;
    hands[1].button_mask = 1u;

    eng_xr_submit_frame_state(xr, 7u, &head, eyes, hands);
    /* XRWebGLLayer FBO 7 preserved! */
    assert(eng_xr_framebuffer(xr) == 7u);
    eng_xr_sync_frame(xr, eng_v3(0.0f, 5.0f, 10.0f), eng_quat_identity(), inp);
    assert(eng_xr_get_eye(xr, 0) != NULL && eng_xr_get_eye(xr, 1)->viewport[0] == 1024);
    assert(eng_xr_get_eye(xr, 2) == NULL);
    assert(eng_xr_get_head(xr)->tracked && eng_xr_get_hand(xr, 1)->trigger > 0.8f);
    assert(fabsf(eng_input_axis(inp, "move_x") - (-0.75f)) < 0.01f);
    assert(eng_input_down(inp, "fire") && eng_input_down(inp, "jump"));

    eng_xr_end_session(xr);
    assert(!eng_xr_is_active(xr) && eng_xr_framebuffer(xr) == 0u);
    eng_xr_destroy(xr);

    /* Quit event */
    memset(&ev, 0, sizeof(ev));
    ev.type = SDL_EVENT_QUIT;
    eng_input_process_event(inp, plat, &ev);
    assert(eng_platform_should_quit(plat));

    eng_input_destroy(inp);
    eng_platform_destroy(plat);
}

int main(void) {
    test_gl_loader_and_mock();
    test_platform_and_input_and_xr();
    printf("[PASS] Phase 2 SDL3 Platform, GL Loader, Input/Touch & WebXR tests succeeded\n");
    return 0;
}
