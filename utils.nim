
proc first*[T](s: openArray[T]; pred: proc (x: T): bool {.closure.}): T {.inline.} =
    for item in s:
        if pred(item):
            return item

    return nil
        