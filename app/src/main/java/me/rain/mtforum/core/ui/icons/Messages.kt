// Copyright 2025-2026, compose-miuix-ui contributors
// SPDX-License-Identifier: Apache-2.0
// Source: https://github.com/compose-miuix-ui/miuix/blob/8972f941c194bd3c4e14c34543d5ebc7b39e40da/miuix-icons/src/commonMain/kotlin/top/yukonga/miuix/kmp/icon/extended/Messages.kt
// Adaptation: retain the Regular vector unchanged; change only package and receiver.
package me.rain.mtforum.core.ui.icons

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.PathFillType
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.graphics.vector.PathNode
import androidx.compose.ui.graphics.vector.group
import androidx.compose.ui.unit.dp

val MiuixNavigationIcons.Messages: ImageVector
    get() {
        if (_messagesRegular != null) return _messagesRegular!!
        _messagesRegular = ImageVector.Builder(
            name = "Messages.Regular",
            defaultWidth = 24.0f.dp,
            defaultHeight = 24.0f.dp,
            viewportWidth = 1263.6f,
            viewportHeight = 1263.6f,
        ).apply {
            group(scaleY = -1.0f, translationY = 1263.6f) {
                addPath(
                    pathData = listOf(
                        PathNode.MoveTo(258.3f, 380.8f),
                        PathNode.QuadTo(188.3f, 438.8f, 146.8f, 517.8f),
                        PathNode.QuadTo(105.3f, 596.8f, 105.3f, 686.8f),
                        PathNode.QuadTo(105.3f, 814.8f, 180.8f, 913.8f),
                        PathNode.QuadTo(256.3f, 1012.8f, 377.8f, 1066.8f),
                        PathNode.QuadTo(499.3f, 1120.8f, 632.3f, 1120.8f),
                        PathNode.QuadTo(773.3f, 1120.8f, 894.3f, 1064.3f),
                        PathNode.QuadTo(1015.3f, 1007.8f, 1086.8f, 908.3f),
                        PathNode.QuadTo(1158.3f, 808.8f, 1158.3f, 686.8f),
                        PathNode.QuadTo(1158.3f, 559.8f, 1100.8f, 473.8f),
                        PathNode.QuadTo(1043.3f, 387.8f, 949.3f, 329.8f),
                        PathNode.QuadTo(893.3f, 295.8f, 847.3f, 278.3f),
                        PathNode.QuadTo(801.3f, 260.8f, 723.3f, 237.8f),
                        PathNode.LineTo(698.3f, 230.8f),
                        PathNode.QuadTo(649.3f, 215.8f, 506.3f, 174.8f),
                        PathNode.LineTo(398.3f, 143.8f),
                        PathNode.QuadTo(393.3f, 142.8f, 389.3f, 146.8f),
                        PathNode.QuadTo(385.3f, 150.8f, 387.3f, 155.8f),
                        PathNode.LineTo(421.3f, 269.8f),
                        PathNode.QuadTo(423.3f, 277.8f, 420.3f, 284.3f),
                        PathNode.QuadTo(417.3f, 290.8f, 409.3f, 293.8f),
                        PathNode.QuadTo(322.3f, 326.8f, 258.3f, 380.8f),
                        PathNode.Close,
                    ),
                    fill = SolidColor(Color.Black),
                    fillAlpha = 1f,
                    pathFillType = PathFillType.NonZero,
                )
            }
        }.build()
        return _messagesRegular!!
    }


private var _messagesRegular: ImageVector? = null

