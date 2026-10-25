// Copyright 2025, compose-miuix-ui contributors
// SPDX-License-Identifier: Apache-2.0

package me.rain.mtforum.core.ui.icons

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.PathFillType
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.graphics.vector.PathNode
import androidx.compose.ui.graphics.vector.group
import androidx.compose.ui.unit.dp

val MiuixNavigationIcons.Months: ImageVector
    get() {
        if (_monthsRegular != null) return _monthsRegular!!
        _monthsRegular =
            ImageVector.Builder(
                    name = "Months.Regular",
                    defaultWidth = 24.0f.dp,
                    defaultHeight = 24.0f.dp,
                    viewportWidth = 1197.6f,
                    viewportHeight = 1197.6f,
                )
                .apply {
                    group(scaleY = -1.0f, translationY = 1197.6f) {
                        addPath(
                            pathData =
                                listOf(
                                    PathNode.MoveTo(850.3f, 651.4f),
                                    PathNode.VerticalTo(676.4f),
                                    PathNode.QuadTo(850.3f, 695.5f, 842.9f, 703.8f),
                                    PathNode.QuadTo(835.4f, 712.0f, 818.2f, 712.0f),
                                    PathNode.HorizontalTo(380.4f),
                                    PathNode.QuadTo(363.4f, 712.0f, 355.9f, 703.6f),
                                    PathNode.QuadTo(348.4f, 695.3f, 348.4f, 676.4f),
                                    PathNode.VerticalTo(651.4f),
                                    PathNode.QuadTo(348.4f, 632.5f, 355.9f, 624.6f),
                                    PathNode.QuadTo(363.4f, 616.7f, 380.4f, 616.7f),
                                    PathNode.HorizontalTo(818.2f),
                                    PathNode.QuadTo(835.4f, 616.7f, 842.9f, 624.6f),
                                    PathNode.QuadTo(850.3f, 632.5f, 850.3f, 651.4f),
                                    PathNode.Close,
                                    PathNode.MoveTo(656.9f, 449.1f),
                                    PathNode.VerticalTo(474.2f),
                                    PathNode.QuadTo(656.9f, 493.0f, 649.5f, 501.4f),
                                    PathNode.QuadTo(642.0f, 509.8f, 624.8f, 509.8f),
                                    PathNode.HorizontalTo(380.4f),
                                    PathNode.QuadTo(363.4f, 509.8f, 355.9f, 501.4f),
                                    PathNode.QuadTo(348.4f, 493.0f, 348.4f, 474.2f),
                                    PathNode.VerticalTo(449.1f),
                                    PathNode.QuadTo(348.4f, 430.3f, 355.9f, 422.3f),
                                    PathNode.QuadTo(363.4f, 414.4f, 380.4f, 414.4f),
                                    PathNode.HorizontalTo(624.8f),
                                    PathNode.QuadTo(642.0f, 414.4f, 649.5f, 422.3f),
                                    PathNode.QuadTo(656.9f, 430.3f, 656.9f, 449.1f),
                                    PathNode.Close,
                                    PathNode.MoveTo(978.3f, 182.9f),
                                    PathNode.QuadTo(1025.4f, 207.8f, 1046.5f, 251.4f),
                                    PathNode.QuadTo(1058.8f, 275.1f, 1061.6f, 307.9f),
                                    PathNode.QuadTo(1064.4f, 340.8f, 1064.4f, 415.9f),
                                    PathNode.VerticalTo(781.7f),
                                    PathNode.QuadTo(1064.4f, 856.9f, 1061.6f, 889.3f),
                                    PathNode.QuadTo(1058.8f, 921.8f, 1046.5f, 945.5f),
                                    PathNode.QuadTo(1035.9f, 967.3f, 1018.0f, 985.3f),
                                    PathNode.QuadTo(1000.1f, 1003.3f, 978.3f, 1014.7f),
                                    PathNode.QuadTo(954.6f, 1026.1f, 922.1f, 1028.8f),
                                    PathNode.QuadTo(889.6f, 1031.6f, 814.5f, 1031.6f),
                                    PathNode.HorizontalTo(383.1f),
                                    PathNode.QuadTo(308.0f, 1031.6f, 275.5f, 1028.8f),
                                    PathNode.QuadTo(243.0f, 1026.1f, 219.3f, 1014.7f),
                                    PathNode.QuadTo(197.5f, 1003.3f, 179.6f, 985.3f),
                                    PathNode.QuadTo(161.8f, 967.3f, 151.1f, 945.5f),
                                    PathNode.QuadTo(138.8f, 921.8f, 136.0f, 889.3f),
                                    PathNode.QuadTo(133.2f, 856.9f, 133.2f, 781.7f),
                                    PathNode.VerticalTo(415.9f),
                                    PathNode.QuadTo(133.2f, 340.8f, 136.0f, 307.9f),
                                    PathNode.QuadTo(138.8f, 275.1f, 151.1f, 251.4f),
                                    PathNode.QuadTo(172.2f, 207.8f, 219.3f, 182.9f),
                                    PathNode.QuadTo(243.0f, 171.5f, 275.5f, 168.8f),
                                    PathNode.QuadTo(308.0f, 166.0f, 383.1f, 166.0f),
                                    PathNode.HorizontalTo(814.5f),
                                    PathNode.QuadTo(889.6f, 166.0f, 922.1f, 168.8f),
                                    PathNode.QuadTo(954.6f, 171.5f, 978.3f, 182.9f),
                                    PathNode.Close,
                                    PathNode.MoveTo(265.6f, 268.3f),
                                    PathNode.QuadTo(246.4f, 277.8f, 236.5f, 297.5f),
                                    PathNode.QuadTo(231.4f, 307.2f, 230.0f, 321.7f),
                                    PathNode.QuadTo(228.6f, 336.2f, 228.6f, 369.8f),
                                    PathNode.VerticalTo(705.8f),
                                    PathNode.QuadTo(228.6f, 740.1f, 230.0f, 754.3f),
                                    PathNode.QuadTo(231.4f, 768.4f, 236.5f, 778.1f),
                                    PathNode.QuadTo(246.2f, 797.3f, 265.6f, 807.1f),
                                    PathNode.QuadTo(275.1f, 812.4f, 289.3f, 813.6f),
                                    PathNode.QuadTo(303.6f, 814.9f, 337.9f, 814.9f),
                                    PathNode.HorizontalTo(859.7f),
                                    PathNode.QuadTo(894.7f, 814.9f, 908.6f, 813.6f),
                                    PathNode.QuadTo(922.5f, 812.4f, 932.0f, 807.1f),
                                    PathNode.QuadTo(951.4f, 797.3f, 961.2f, 778.1f),
                                    PathNode.QuadTo(966.2f, 768.4f, 967.6f, 754.2f),
                                    PathNode.QuadTo(969.0f, 739.9f, 969.0f, 705.8f),
                                    PathNode.VerticalTo(369.5f),
                                    PathNode.QuadTo(969.0f, 335.9f, 967.6f, 321.6f),
                                    PathNode.QuadTo(966.2f, 307.2f, 961.2f, 297.5f),
                                    PathNode.QuadTo(951.2f, 277.8f, 932.0f, 268.3f),
                                    PathNode.QuadTo(922.5f, 263.3f, 907.5f, 262.0f),
                                    PathNode.QuadTo(892.5f, 260.7f, 859.7f, 260.7f),
                                    PathNode.HorizontalTo(337.9f),
                                    PathNode.QuadTo(305.8f, 260.7f, 290.4f, 262.0f),
                                    PathNode.QuadTo(275.1f, 263.3f, 265.6f, 268.3f),
                                    PathNode.Close,
                                ),
                            fill = SolidColor(Color.Black),
                            fillAlpha = 1f,
                            pathFillType = PathFillType.NonZero,
                        )
                    }
                }
                .build()
        return _monthsRegular!!
    }

private var _monthsRegular: ImageVector? = null
