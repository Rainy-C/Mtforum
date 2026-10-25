// Copyright 2025-2026, compose-miuix-ui contributors
// SPDX-License-Identifier: Apache-2.0
// Source: https://github.com/compose-miuix-ui/miuix/blob/8972f941c194bd3c4e14c34543d5ebc7b39e40da/miuix-icons/src/commonMain/kotlin/top/yukonga/miuix/kmp/icon/extended/ContactsCircle.kt
// Adaptation: retain the Regular vector unchanged; change only package and receiver.
package me.rain.mtforum.core.ui.icons

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.PathFillType
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.graphics.vector.PathNode
import androidx.compose.ui.graphics.vector.group
import androidx.compose.ui.unit.dp

val MiuixNavigationIcons.Profile: ImageVector
    get() {
        if (_contactscircleRegular != null) return _contactscircleRegular!!
        _contactscircleRegular = ImageVector.Builder(
            name = "ContactsCircle.Regular",
            defaultWidth = 24.0f.dp,
            defaultHeight = 24.0f.dp,
            viewportWidth = 1197.6f,
            viewportHeight = 1197.6f,
        ).apply {
            group(scaleY = -1.0f, translationY = 1197.6f) {
                addPath(
                    pathData = listOf(
                        PathNode.MoveTo(1097.8f, 598.3f),
                        PathNode.QuadTo(1097.8f, 734.3f, 1030.8f, 848.8f),
                        PathNode.QuadTo(963.8f, 963.3f, 848.8f, 1030.3f),
                        PathNode.QuadTo(733.8f, 1097.3f, 598.8f, 1097.3f),
                        PathNode.QuadTo(463.8f, 1097.3f, 348.8f, 1030.3f),
                        PathNode.QuadTo(233.8f, 963.3f, 166.8f, 848.8f),
                        PathNode.QuadTo(99.8f, 734.3f, 99.8f, 598.3f),
                        PathNode.QuadTo(99.8f, 463.3f, 166.8f, 348.8f),
                        PathNode.QuadTo(233.8f, 234.3f, 348.8f, 167.3f),
                        PathNode.QuadTo(463.8f, 100.3f, 598.8f, 100.3f),
                        PathNode.QuadTo(733.8f, 100.3f, 848.8f, 167.3f),
                        PathNode.QuadTo(963.8f, 234.3f, 1030.8f, 348.8f),
                        PathNode.QuadTo(1097.8f, 463.3f, 1097.8f, 598.3f),
                        PathNode.Close,
                        PathNode.MoveTo(871.8f, 194.3f),
                        PathNode.QuadTo(902.8f, 211.3f, 927.8f, 236.3f),
                        PathNode.QuadTo(952.8f, 261.3f, 968.8f, 292.3f),
                        PathNode.QuadTo(970.8f, 298.3f, 967.8f, 302.3f),
                        PathNode.QuadTo(892.8f, 411.3f, 797.8f, 471.8f),
                        PathNode.QuadTo(702.8f, 532.3f, 598.8f, 532.3f),
                        PathNode.QuadTo(494.8f, 532.3f, 399.8f, 471.8f),
                        PathNode.QuadTo(304.8f, 411.3f, 229.8f, 302.3f),
                        PathNode.QuadTo(228.8f, 299.3f, 227.8f, 295.3f),
                        PathNode.QuadTo(228.8f, 294.3f, 228.8f, 292.3f),
                        PathNode.QuadTo(261.8f, 228.3f, 325.8f, 194.3f),
                        PathNode.QuadTo(358.8f, 177.3f, 405.3f, 173.8f),
                        PathNode.QuadTo(451.8f, 170.3f, 560.8f, 170.3f),
                        PathNode.HorizontalTo(636.8f),
                        PathNode.QuadTo(745.8f, 170.3f, 792.3f, 173.8f),
                        PathNode.QuadTo(838.8f, 177.3f, 871.8f, 194.3f),
                        PathNode.Close,
                        PathNode.MoveTo(194.8f, 598.3f),
                        PathNode.QuadTo(194.8f, 708.3f, 249.3f, 800.8f),
                        PathNode.QuadTo(303.8f, 893.3f, 396.3f, 947.8f),
                        PathNode.QuadTo(488.8f, 1002.3f, 598.8f, 1002.3f),
                        PathNode.QuadTo(708.8f, 1002.3f, 801.3f, 947.8f),
                        PathNode.QuadTo(893.8f, 893.3f, 948.3f, 800.8f),
                        PathNode.QuadTo(1002.8f, 708.3f, 1002.8f, 598.3f),
                        PathNode.QuadTo(1002.8f, 488.3f, 948.3f, 395.8f),
                        PathNode.QuadTo(893.8f, 303.3f, 801.3f, 249.3f),
                        PathNode.QuadTo(708.8f, 195.3f, 598.8f, 195.3f),
                        PathNode.QuadTo(488.8f, 195.3f, 396.3f, 249.3f),
                        PathNode.QuadTo(303.8f, 303.3f, 249.3f, 395.8f),
                        PathNode.QuadTo(194.8f, 488.3f, 194.8f, 598.3f),
                        PathNode.Close,
                        PathNode.MoveTo(755.8f, 739.3f),
                        PathNode.QuadTo(755.8f, 782.3f, 734.8f, 818.3f),
                        PathNode.QuadTo(713.8f, 854.3f, 677.8f, 875.3f),
                        PathNode.QuadTo(641.8f, 896.3f, 598.8f, 896.3f),
                        PathNode.QuadTo(555.8f, 896.3f, 519.8f, 875.3f),
                        PathNode.QuadTo(483.8f, 854.3f, 462.8f, 818.3f),
                        PathNode.QuadTo(441.8f, 782.3f, 441.8f, 739.3f),
                        PathNode.QuadTo(441.8f, 697.3f, 462.8f, 660.8f),
                        PathNode.QuadTo(483.8f, 624.3f, 519.8f, 603.3f),
                        PathNode.QuadTo(555.8f, 582.3f, 598.8f, 582.3f),
                        PathNode.QuadTo(641.8f, 582.3f, 677.8f, 603.3f),
                        PathNode.QuadTo(713.8f, 624.3f, 734.8f, 660.8f),
                        PathNode.QuadTo(755.8f, 697.3f, 755.8f, 739.3f),
                        PathNode.Close,
                    ),
                    fill = SolidColor(Color.Black),
                    fillAlpha = 1f,
                    pathFillType = PathFillType.NonZero,
                )
            }
        }.build()
        return _contactscircleRegular!!
    }


private var _contactscircleRegular: ImageVector? = null

