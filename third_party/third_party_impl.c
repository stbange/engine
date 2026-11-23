/* Dedicated compilation unit for single-header MIT libraries (stb + cgltf). */

#define STB_IMAGE_IMPLEMENTATION
#include "stb_image.h"

#define STB_IMAGE_WRITE_IMPLEMENTATION
#include "stb_image_write.h"

#define STB_TRUETYPE_IMPLEMENTATION
#include "stb_truetype.h"

#include "stb_vorbis.c"

#define CGLTF_IMPLEMENTATION
#include "cgltf.h"
