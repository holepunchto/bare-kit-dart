#include <stdint.h>
#include <stdlib.h>

#include "dart_api_dl.h"

// A worklet may exit after the isolate that started it has shut down, which a
// NativeCallable does not survive. Posting to the port of an isolate that has
// shut down is ignored instead.

DART_EXPORT void *
bare_kit_dart_port_create(int64_t port) {
  Dart_Port_DL *result = malloc(sizeof(Dart_Port_DL));

  if (result != NULL) *result = port;

  return result;
}

DART_EXPORT void
bare_kit_dart_port_destroy(void *port) {
  free(port);
}

DART_EXPORT void
bare_kit_dart_on_exit(int code, void *data) {
  Dart_PostInteger_DL(*(Dart_Port_DL *) data, code);

  bare_kit_dart_port_destroy(data);
}
