#ifndef TAGGO_SHIM_H
#define TAGGO_SHIM_H

#include <stdlib.h>
#include <string.h>
#include <tag_c.h>

// Helper per le copertine: la macro TAGLIB_COMPLEX_PROPERTY_PICTURE
// non è utilizzabile direttamente da Swift.

static inline BOOL taggo_set_front_cover(TagLib_File *file, const char *data,
                                         unsigned int size, const char *mime) {
    TAGLIB_COMPLEX_PROPERTY_PICTURE(props, data, size, "", mime, "Front Cover");
    return taglib_complex_property_set(file, "PICTURE", props);
}

static inline BOOL taggo_remove_pictures(TagLib_File *file) {
    return taglib_complex_property_set(file, "PICTURE", NULL);
}

static inline BOOL taggo_has_pictures(const TagLib_File *file) {
    char **keys = taglib_complex_property_keys(file);
    BOOL found = 0;
    if (keys) {
        for (char **k = keys; *k; k++) {
            if (strcmp(*k, "PICTURE") == 0) { found = 1; break; }
        }
        taglib_complex_property_free_keys(keys);
    }
    return found;
}

// Restituisce una copia (da liberare con free) della prima immagine incorporata.
static inline char *taggo_copy_first_picture(const TagLib_File *file, unsigned int *size) {
    *size = 0;
    TagLib_Complex_Property_Attribute ***props = taglib_complex_property_get(file, "PICTURE");
    if (!props) return NULL;
    TagLib_Complex_Property_Picture_Data picture;
    memset(&picture, 0, sizeof picture);
    taglib_picture_from_complex_property(props, &picture);
    char *out = NULL;
    if (picture.data && picture.size > 0) {
        out = malloc(picture.size);
        if (out) {
            memcpy(out, picture.data, picture.size);
            *size = picture.size;
        }
    }
    taglib_complex_property_free(props);
    return out;
}

#endif
