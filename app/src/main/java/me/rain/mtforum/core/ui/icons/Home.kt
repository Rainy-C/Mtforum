// Copyright 2025-2026, compose-miuix-ui contributors
// SPDX-License-Identifier: Apache-2.0
// Source: https://github.com/compose-miuix-ui/miuix/blob/8972f941c194bd3c4e14c34543d5ebc7b39e40da/miuix-icons/src/commonMain/kotlin/top/yukonga/miuix/kmp/icon/extended/Home.kt
// Adaptation: retain the Regular vector unchanged; change only package and receiver.
package me.rain.mtforum.core.ui.icons

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.PathFillType
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.graphics.vector.PathNode
import androidx.compose.ui.unit.dp

val MiuixNavigationIcons.Home: ImageVector
    get() {
        if (_homeRegular != null) return _homeRegular!!
        _homeRegular = ImageVector.Builder(
            name = "Home.Regular",
            defaultWidth = 24.0f.dp,
            defaultHeight = 24.0f.dp,
            viewportWidth = 24.0f,
            viewportHeight = 24.0f,
        ).apply {
            addPath(
                pathData = listOf(
                    PathNode.MoveTo(2.243f, 10.404f),
                    PathNode.CurveTo(2.125f, 10.848f, 2.125f, 11.328f, 2.125f, 12.286f),
                    PathNode.LineTo(2.125f, 17.205f),
                    PathNode.CurveTo(2.125f, 18.883f, 2.125f, 19.722f, 2.451f, 20.363f),
                    PathNode.CurveTo(2.738f, 20.927f, 3.196f, 21.386f, 3.761f, 21.673f),
                    PathNode.CurveTo(4.402f, 22.0f, 5.241f, 22.0f, 6.919f, 22.0f),
                    PathNode.LineTo(7.164f, 22.0f),
                    PathNode.CurveTo(7.836f, 22.0f, 8.171f, 22.0f, 8.428f, 21.869f),
                    PathNode.CurveTo(8.653f, 21.754f, 8.836f, 21.571f, 8.951f, 21.346f),
                    PathNode.CurveTo(9.082f, 21.089f, 9.082f, 20.754f, 9.082f, 20.082f),
                    PathNode.LineTo(9.082f, 17.57f),
                    PathNode.CurveTo(9.082f, 15.959f, 10.388f, 14.653f, 11.999f, 14.653f),
                    PathNode.CurveTo(13.609f, 14.653f, 14.915f, 15.959f, 14.915f, 17.57f),
                    PathNode.LineTo(14.915f, 20.082f),
                    PathNode.CurveTo(14.915f, 20.754f, 14.915f, 21.089f, 15.047f, 21.346f),
                    PathNode.CurveTo(15.161f, 21.571f, 15.345f, 21.754f, 15.57f, 21.869f),
                    PathNode.CurveTo(15.826f, 22.0f, 16.162f, 22.0f, 16.833f, 22.0f),
                    PathNode.LineTo(17.08f, 22.0f),
                    PathNode.CurveTo(18.758f, 22.0f, 19.597f, 22.0f, 20.238f, 21.673f),
                    PathNode.CurveTo(20.802f, 21.386f, 21.261f, 20.927f, 21.548f, 20.363f),
                    PathNode.CurveTo(21.875f, 19.722f, 21.875f, 18.883f, 21.875f, 17.205f),
                    PathNode.LineTo(21.875f, 12.286f),
                    PathNode.CurveTo(21.875f, 11.327f, 21.875f, 10.848f, 21.756f, 10.404f),
                    PathNode.CurveTo(21.65f, 10.01f, 21.476f, 9.638f, 21.243f, 9.303f),
                    PathNode.CurveTo(20.979f, 8.926f, 20.611f, 8.619f, 19.877f, 8.002f),
                    PathNode.LineTo(14.055f, 3.114f),
                    PathNode.CurveTo(13.324f, 2.501f, 12.959f, 2.194f, 12.55f, 2.078f),
                    PathNode.CurveTo(12.19f, 1.974f, 11.808f, 1.974f, 11.449f, 2.078f),
                    PathNode.CurveTo(11.04f, 2.194f, 10.675f, 2.501f, 9.944f, 3.114f),
                    PathNode.LineTo(4.122f, 8.002f),
                    PathNode.CurveTo(3.387f, 8.619f, 3.02f, 8.926f, 2.756f, 9.303f),
                    PathNode.CurveTo(2.523f, 9.638f, 2.349f, 10.01f, 2.243f, 10.404f),
                    PathNode.Close,
                ),
                fill = SolidColor(Color.Black),
                fillAlpha = 1f,
                pathFillType = PathFillType.NonZero,
            )
        }.build()
        return _homeRegular!!
    }


private var _homeRegular: ImageVector? = null

