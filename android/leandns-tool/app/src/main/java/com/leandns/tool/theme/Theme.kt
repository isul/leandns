package com.leandns.tool.theme

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.sp

private val Forest = Color(0xFF0B6E4F)
private val Mint = Color(0xFF3ECF8E)
private val DeepPanel = Color(0xFF1A222C)
private val DeepBg = Color(0xFF0F1419)
private val Sidebar = Color(0xFF102A28)
private val SoftText = Color(0xFFE8EEF4)
private val Muted = Color(0xFF9AA8B5)
private val LightBg = Color(0xFFF3F5F7)
private val LightPanel = Color(0xFFFFFFFF)
private val LightText = Color(0xFF1A2330)
private val LightMuted = Color(0xFF5C6B7A)
private val Danger = Color(0xFFF97066)
private val Warn = Color(0xFFFDB022)

private val DarkColors = darkColorScheme(
    primary = Mint,
    onPrimary = Sidebar,
    secondary = Forest,
    onSecondary = SoftText,
    background = DeepBg,
    onBackground = SoftText,
    surface = DeepPanel,
    onSurface = SoftText,
    surfaceVariant = Sidebar,
    onSurfaceVariant = Muted,
    error = Danger,
    onError = SoftText,
    outline = Color(0xFF2C3845),
    tertiary = Warn,
)

private val LightColors = lightColorScheme(
    primary = Forest,
    onPrimary = Color.White,
    secondary = Color(0xFF1B9C85),
    onSecondary = Color.White,
    background = LightBg,
    onBackground = LightText,
    surface = LightPanel,
    onSurface = LightText,
    surfaceVariant = Color(0xFFE7F3EF),
    onSurfaceVariant = LightMuted,
    error = Color(0xFFB42318),
    onError = Color.White,
    outline = Color(0xFFD5DDE5),
    tertiary = Color(0xFF9A6700),
)

private val LeanTypography = androidx.compose.material3.Typography(
    displayLarge = TextStyle(
        fontFamily = FontFamily.Serif,
        fontWeight = FontWeight.Bold,
        fontSize = 40.sp,
        letterSpacing = (-0.5).sp,
    ),
    headlineMedium = TextStyle(
        fontFamily = FontFamily.Serif,
        fontWeight = FontWeight.SemiBold,
        fontSize = 26.sp,
        letterSpacing = (-0.3).sp,
    ),
    titleLarge = TextStyle(
        fontFamily = FontFamily.SansSerif,
        fontWeight = FontWeight.SemiBold,
        fontSize = 20.sp,
    ),
    titleMedium = TextStyle(
        fontFamily = FontFamily.SansSerif,
        fontWeight = FontWeight.Medium,
        fontSize = 16.sp,
    ),
    bodyLarge = TextStyle(
        fontFamily = FontFamily.SansSerif,
        fontWeight = FontWeight.Normal,
        fontSize = 16.sp,
        lineHeight = 24.sp,
    ),
    bodyMedium = TextStyle(
        fontFamily = FontFamily.SansSerif,
        fontWeight = FontWeight.Normal,
        fontSize = 14.sp,
        lineHeight = 20.sp,
    ),
    labelLarge = TextStyle(
        fontFamily = FontFamily.Monospace,
        fontWeight = FontWeight.Medium,
        fontSize = 13.sp,
    ),
)

@Composable
fun LeanDnsTheme(
    darkTheme: Boolean = isSystemInDarkTheme(),
    content: @Composable () -> Unit,
) {
    MaterialTheme(
        colorScheme = if (darkTheme) DarkColors else LightColors,
        typography = LeanTypography,
        content = content,
    )
}
