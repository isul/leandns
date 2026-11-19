package com.leandns.tool

import android.content.Context
import androidx.annotation.StringRes

/** Resolves string resources; injectable for unit tests. */
fun interface StringLookup {
    fun get(@StringRes id: Int, vararg formatArgs: Any): String
}

fun Context.asStringLookup(): StringLookup = StringLookup { id, args ->
    if (args.isEmpty()) getString(id) else getString(id, *args)
}
