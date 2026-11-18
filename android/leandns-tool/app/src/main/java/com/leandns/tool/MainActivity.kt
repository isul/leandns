package com.leandns.tool

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.material3.Surface
import androidx.compose.ui.Modifier
import androidx.lifecycle.viewmodel.compose.viewModel
import com.leandns.tool.theme.LeanDnsTheme
import com.leandns.tool.ui.ToolScreen

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent {
            LeanDnsTheme {
                val viewModel: ToolViewModel = viewModel()
                Surface(modifier = Modifier.fillMaxSize()) {
                    ToolScreen(
                        viewModel = viewModel,
                        modifier = Modifier.safeDrawingPadding(),
                    )
                }
            }
        }
    }
}
