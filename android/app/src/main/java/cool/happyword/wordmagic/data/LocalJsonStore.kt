package cool.happyword.wordmagic.data

import android.content.Context
import java.io.File

class LocalJsonStore(context: Context, private val fileName: String) {
    private val file: File = File(context.filesDir, fileName)

    fun readOrNull(): String? {
        return if (file.exists()) file.readText() else null
    }

    fun write(value: String) {
        file.parentFile?.mkdirs()
        file.writeText(value)
    }
}
