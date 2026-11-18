package me.rain.mtforum.core.ui.icons

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.PathFillType
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.graphics.vector.PathNode
import androidx.compose.ui.unit.dp

/** Small filled flame for Discuz featured (digest) threads. */
val MiuixNavigationIcons.Flame: ImageVector
    get() {
        if (featuredFlame != null) return featuredFlame!!
        featuredFlame = ImageVector.Builder(
            name = "Featured.Flame",
            defaultWidth = 24.dp,
            defaultHeight = 24.dp,
            viewportWidth = 24f,
            viewportHeight = 24f,
        ).apply {
            addPath(
                pathData = listOf(
                    PathNode.MoveTo(12f, 2f),
                    PathNode.CurveTo(11.5f, 5f, 9.5f, 7f, 9.5f, 9.5f),
                    PathNode.CurveTo(9.5f, 11f, 10.4f, 12f, 11.5f, 12.5f),
                    PathNode.CurveTo(13.7f, 10.3f, 15.4f, 7.5f, 15f, 4.4f),
                    PathNode.CurveTo(19f, 7.6f, 21f, 11.1f, 21f, 15.5f),
                    PathNode.CurveTo(21f, 20f, 17.1f, 23f, 12f, 23f),
                    PathNode.CurveTo(6.9f, 23f, 3f, 20f, 3f, 15.5f),
                    PathNode.CurveTo(3f, 11.9f, 5f, 8.8f, 7.6f, 6f),
                    PathNode.CurveTo(7.3f, 9.4f, 8.2f, 11.8f, 9f, 13.1f),
                    PathNode.CurveTo(8.9f, 8.8f, 11f, 5.5f, 12f, 2f),
                    PathNode.Close,
                ),
                fill = SolidColor(Color.Black),
                pathFillType = PathFillType.NonZero,
            )
        }.build()
        return featuredFlame!!
    }

private var featuredFlame: ImageVector? = null
