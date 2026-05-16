@file:Suppress("OVERRIDE_DEPRECATION")

package cool.happyword.wordmagic

import android.os.Bundle
import android.view.WindowManager
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import cool.happyword.wordmagic.ui.navigation.WordMagicGameApp

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        @Suppress("DEPRECATION")
        window.setFlags(WindowManager.LayoutParams.FLAG_FULLSCREEN, WindowManager.LayoutParams.FLAG_FULLSCREEN)
        setContent {
            WordMagicGameApp()
        }
    }
}
