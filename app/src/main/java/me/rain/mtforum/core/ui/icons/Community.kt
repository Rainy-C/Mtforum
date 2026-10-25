// Copyright 2025-2026, compose-miuix-ui contributors
// SPDX-License-Identifier: Apache-2.0
// Source: https://github.com/compose-miuix-ui/miuix/blob/8972f941c194bd3c4e14c34543d5ebc7b39e40da/miuix-icons/src/commonMain/kotlin/top/yukonga/miuix/kmp/icon/extended/Community.kt
// Adaptation: retain the Regular vector unchanged; change only package and receiver.
package me.rain.mtforum.core.ui.icons

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.PathFillType
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.graphics.vector.PathNode
import androidx.compose.ui.graphics.vector.group
import androidx.compose.ui.unit.dp

val MiuixNavigationIcons.Community: ImageVector
    get() {
        if (_communityRegular != null) return _communityRegular!!
        _communityRegular = ImageVector.Builder(
            name = "Community.Regular",
            defaultWidth = 24.0f.dp,
            defaultHeight = 24.0f.dp,
            viewportWidth = 1178.4f,
            viewportHeight = 1178.4f,
        ).apply {
            group(scaleY = -1.0f, translationY = 1178.4f) {
                addPath(
                    pathData = listOf(
                        PathNode.MoveTo(135.4f, 166.9f),
                        PathNode.QuadTo(126.3f, 182.3f, 122.4f, 204.6f),
                        PathNode.QuadTo(118.6f, 226.9f, 118.6f, 281.9f),
                        PathNode.VerticalTo(749.8f),
                        PathNode.QuadTo(118.6f, 838.6f, 121.5f, 876.5f),
                        PathNode.QuadTo(124.4f, 914.4f, 137.9f, 941.6f),
                        PathNode.QuadTo(165.9f, 995.0f, 218.2f, 1021.8f),
                        PathNode.QuadTo(245.4f, 1035.5f, 283.8f, 1038.8f),
                        PathNode.QuadTo(322.2f, 1042.2f, 411.1f, 1042.2f),
                        PathNode.HorizontalTo(767.4f),
                        PathNode.QuadTo(856.3f, 1042.2f, 894.2f, 1038.8f),
                        PathNode.QuadTo(932.1f, 1035.5f, 959.3f, 1021.8f),
                        PathNode.QuadTo(985.3f, 1009.3f, 1006.1f, 988.5f),
                        PathNode.QuadTo(1027.0f, 967.7f, 1039.5f, 941.6f),
                        PathNode.QuadTo(1053.2f, 914.4f, 1056.5f, 876.5f),
                        PathNode.QuadTo(1059.8f, 838.6f, 1059.8f, 749.8f),
                        PathNode.VerticalTo(564.9f),
                        PathNode.QuadTo(1059.8f, 476.1f, 1056.5f, 437.7f),
                        PathNode.QuadTo(1053.2f, 399.3f, 1039.5f, 372.2f),
                        PathNode.QuadTo(1012.3f, 319.9f, 959.3f, 291.9f),
                        PathNode.QuadTo(932.1f, 278.4f, 894.2f, 275.5f),
                        PathNode.QuadTo(856.3f, 272.5f, 767.4f, 272.5f),
                        PathNode.HorizontalTo(506.3f),
                        PathNode.QuadTo(483.4f, 272.5f, 466.9f, 272.1f),
                        PathNode.QuadTo(450.3f, 271.6f, 439.2f, 268.7f),
                        PathNode.QuadTo(420.2f, 266.1f, 397.0f, 255.6f),
                        PathNode.QuadTo(379.7f, 247.2f, 341.1f, 219.7f),
                        PathNode.LineTo(316.3f, 202.5f),
                        PathNode.QuadTo(262.4f, 165.0f, 238.8f, 151.5f),
                        PathNode.QuadTo(215.2f, 138.1f, 196.8f, 137.2f),
                        PathNode.QuadTo(177.1f, 136.4f, 160.3f, 144.7f),
                        PathNode.QuadTo(143.5f, 153.0f, 135.4f, 166.9f),
                        PathNode.Close,
                        PathNode.MoveTo(354.2f, 543.9f),
                        PathNode.VerticalTo(566.8f),
                        PathNode.QuadTo(354.2f, 585.0f, 362.5f, 591.8f),
                        PathNode.QuadTo(370.7f, 598.6f, 388.9f, 598.6f),
                        PathNode.HorizontalTo(693.2f),
                        PathNode.QuadTo(710.4f, 598.6f, 719.2f, 591.8f),
                        PathNode.QuadTo(727.9f, 585.0f, 727.9f, 568.7f),
                        PathNode.VerticalTo(543.9f),
                        PathNode.QuadTo(727.9f, 526.8f, 719.6f, 519.4f),
                        PathNode.QuadTo(711.3f, 512.1f, 693.2f, 512.1f),
                        PathNode.HorizontalTo(388.9f),
                        PathNode.QuadTo(370.9f, 512.1f, 362.6f, 519.3f),
                        PathNode.QuadTo(354.2f, 526.6f, 354.2f, 543.9f),
                        PathNode.Close,
                        PathNode.MoveTo(365.0f, 337.6f),
                        PathNode.QuadTo(389.2f, 350.3f, 418.2f, 355.1f),
                        PathNode.QuadTo(432.7f, 357.9f, 453.8f, 358.4f),
                        PathNode.QuadTo(474.9f, 358.9f, 503.5f, 358.9f),
                        PathNode.HorizontalTo(809.3f),
                        PathNode.QuadTo(859.8f, 358.9f, 880.9f, 360.7f),
                        PathNode.QuadTo(902.0f, 362.6f, 917.7f, 370.0f),
                        PathNode.QuadTo(947.5f, 385.2f, 961.2f, 414.6f),
                        PathNode.QuadTo(968.7f, 429.3f, 970.6f, 450.9f),
                        PathNode.QuadTo(972.4f, 472.5f, 972.4f, 522.9f),
                        PathNode.VerticalTo(790.7f),
                        PathNode.QuadTo(972.4f, 842.1f, 970.6f, 863.3f),
                        PathNode.QuadTo(968.7f, 884.5f, 961.2f, 899.1f),
                        PathNode.QuadTo(947.4f, 928.6f, 917.7f, 943.7f),
                        PathNode.QuadTo(902.0f, 951.1f, 880.9f, 952.9f),
                        PathNode.QuadTo(859.8f, 954.7f, 809.3f, 954.7f),
                        PathNode.HorizontalTo(369.1f),
                        PathNode.QuadTo(318.6f, 954.7f, 297.1f, 952.9f),
                        PathNode.QuadTo(275.5f, 951.1f, 260.7f, 943.7f),
                        PathNode.QuadTo(230.1f, 929.6f, 216.2f, 899.1f),
                        PathNode.QuadTo(208.7f, 884.5f, 206.9f, 863.3f),
                        PathNode.QuadTo(205.1f, 842.1f, 205.1f, 790.7f),
                        PathNode.VerticalTo(265.7f),
                        PathNode.QuadTo(205.1f, 249.2f, 213.3f, 245.5f),
                        PathNode.QuadTo(221.5f, 241.8f, 239.7f, 255.4f),
                        PathNode.LineTo(293.1f, 292.6f),
                        PathNode.QuadTo(316.0f, 308.8f, 333.9f, 320.3f),
                        PathNode.QuadTo(351.7f, 331.9f, 365.0f, 337.6f),
                        PathNode.Close,
                        PathNode.MoveTo(354.2f, 747.9f),
                        PathNode.VerticalTo(771.6f),
                        PathNode.QuadTo(354.2f, 786.8f, 362.6f, 794.2f),
                        PathNode.QuadTo(370.9f, 801.6f, 387.0f, 801.6f),
                        PathNode.HorizontalTo(790.4f),
                        PathNode.QuadTo(807.5f, 801.6f, 815.9f, 794.7f),
                        PathNode.QuadTo(824.2f, 787.8f, 824.2f, 771.6f),
                        PathNode.VerticalTo(747.9f),
                        PathNode.QuadTo(824.2f, 730.7f, 815.9f, 723.3f),
                        PathNode.QuadTo(807.5f, 716.0f, 790.4f, 716.0f),
                        PathNode.HorizontalTo(387.0f),
                        PathNode.QuadTo(371.7f, 716.0f, 363.0f, 723.4f),
                        PathNode.QuadTo(354.2f, 730.8f, 354.2f, 747.9f),
                        PathNode.Close,
                    ),
                    fill = SolidColor(Color.Black),
                    fillAlpha = 1f,
                    pathFillType = PathFillType.NonZero,
                )
            }
        }.build()
        return _communityRegular!!
    }


private var _communityRegular: ImageVector? = null

